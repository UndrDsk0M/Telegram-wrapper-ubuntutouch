package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"unicode"
	"unicode/utf8"

	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/downloader"
	"github.com/gotd/td/telegram/downloader/fileref"
	"github.com/gotd/td/telegram/message/peer"
	"github.com/gotd/td/tg"
)

type fileRecord struct {
	ID      string `json:"id"`
	Chat    string `json:"chat"`
	Name    string `json:"name"`
	Kind    string `json:"kind"`
	Message int    `json:"message"`
	Date    int    `json:"date"`
	Size    int64  `json:"size"`
}

type fileRow struct {
	fileRecord
	State string `json:"state"`
	Bytes int64  `json:"bytes"`
	Error string `json:"error,omitempty"`
	URL   string `json:"url,omitempty"`
}

type attachment struct {
	fileRecord
	peer     tg.InputPeerClass
	dc       int
	location tg.InputFileLocationClass
}

type download struct {
	id     string
	cancel context.CancelFunc
	done   chan error
	bytes  atomic.Int64
}

type downloads struct {
	root      string
	available map[string]attachment
	saved     map[string]fileRecord
	failed    map[string]string
	active    *download
}

func openDownloads(root string, user int64) *downloads {
	d := &downloads{
		root:      filepath.Join(root, "downloads", strconv.FormatInt(user, 10)),
		available: make(map[string]attachment), saved: make(map[string]fileRecord),
		failed: make(map[string]string),
	}
	entries, _ := os.ReadDir(d.root)
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		data, err := os.ReadFile(filepath.Join(d.root, entry.Name(), "metadata.json"))
		if err != nil {
			continue
		}
		var record fileRecord
		if json.Unmarshal(data, &record) != nil || record.ID != entry.Name() ||
			record.Name != safeName(record.Name) {
			continue
		}
		if info, err := os.Stat(d.filePath(record)); err == nil && info.Mode().IsRegular() &&
			(record.Size <= 0 || info.Size() == record.Size) {
			d.saved[record.ID] = record
		}
	}
	return d
}

func safeName(raw string) string {
	raw = filepath.Base(strings.ReplaceAll(raw, "\\", "/"))
	name := strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || unicode.In(r, unicode.Cf) {
			return -1
		}
		return r
	}, raw)
	name = strings.Trim(name, ". /")
	if name == "" {
		return "attachment"
	}
	if len(name) <= 180 {
		return name
	}
	ext := filepath.Ext(name)
	if len(ext) > 20 {
		ext = ""
	}
	end := 180 - len(ext)
	for !utf8.RuneStart(name[end]) {
		end--
	}
	return name[:end] + ext
}

func photoLocation(photo *tg.Photo) (tg.InputFileLocationClass, int64) {
	var thumb string
	var largest int
	for _, size := range photo.Sizes {
		var kind string
		var bytes int
		switch value := size.(type) {
		case *tg.PhotoSize:
			kind, bytes = value.Type, value.Size
		case *tg.PhotoSizeProgressive:
			if len(value.Sizes) > 0 {
				kind, bytes = value.Type, value.Sizes[len(value.Sizes)-1]
			}
		}
		if kind != "" && bytes > largest {
			thumb, largest = kind, bytes
		}
	}
	if thumb == "" {
		return nil, 0
	}
	return &tg.InputPhotoFileLocation{
		ID: photo.ID, AccessHash: photo.AccessHash, FileReference: photo.FileReference, ThumbSize: thumb,
	}, int64(largest)
}

func documentName(doc *tg.Document, kind string) string {
	for _, attribute := range doc.Attributes {
		if filename, ok := attribute.(*tg.DocumentAttributeFilename); ok && strings.TrimSpace(filename.FileName) != "" {
			return safeName(filename.FileName)
		}
	}
	extensions, _ := mime.ExtensionsByType(doc.MimeType)
	extension := ""
	switch doc.MimeType {
	case "audio/mpeg":
		extension = ".mp3"
	case "audio/ogg":
		extension = ".ogg"
	case "video/mp4":
		extension = ".mp4"
	case "image/jpeg":
		extension = ".jpg"
	default:
		if len(extensions) > 0 {
			extension = extensions[0]
		}
	}
	return safeName(fmt.Sprintf("%s-%d%s", strings.ToLower(kind), doc.ID, extension))
}

func findAttachment(chat string, input tg.InputPeerClass, message *tg.Message, entities peer.Entities) (attachment, bool) {
	var result attachment
	if message.Noforwards || message.TTLPeriod != 0 {
		return result, false
	}
	switch p := message.PeerID.(type) {
	case *tg.PeerChat:
		if entity := entities.Chats()[p.ChatID]; entity != nil && entity.Noforwards {
			return result, false
		}
	case *tg.PeerChannel:
		if entity := entities.Channels()[p.ChannelID]; entity != nil && entity.Noforwards {
			return result, false
		}
	}

	var mediaID int64
	switch media := message.Media.(type) {
	case *tg.MessageMediaPhoto:
		photo, ok := media.Photo.(*tg.Photo)
		if !ok || media.TTLSeconds != 0 {
			return result, false
		}
		result.location, result.Size = photoLocation(photo)
		result.Name, result.Kind = fmt.Sprintf("photo-%d.jpg", photo.ID), "Photo"
		result.dc, mediaID = photo.DCID, photo.ID
	case *tg.MessageMediaDocument:
		doc, ok := media.Document.(*tg.Document)
		if !ok || media.TTLSeconds != 0 {
			return result, false
		}
		kind := "File"
		switch {
		case media.Voice:
			kind = "Voice message"
		case media.Video || media.Round || strings.HasPrefix(doc.MimeType, "video/"):
			kind = "Video"
		case strings.HasPrefix(doc.MimeType, "audio/"):
			kind = "Audio"
		case strings.HasPrefix(doc.MimeType, "image/"):
			kind = "Image"
		}
		result.location = &tg.InputDocumentFileLocation{
			ID: doc.ID, AccessHash: doc.AccessHash, FileReference: doc.FileReference,
		}
		result.Name, result.Kind, result.Size = documentName(doc, kind), kind, doc.Size
		result.dc, mediaID = doc.DCID, doc.ID
	default:
		return result, false
	}
	if result.location == nil || result.dc <= 0 {
		return result, false
	}
	key := sha256.Sum256([]byte(fmt.Sprintf("%s/%d/%T/%d", chat, message.ID, result.location, mediaID)))
	result.ID = hex.EncodeToString(key[:16])
	result.Chat, result.Message, result.Date, result.peer = chat, message.ID, message.Date, input
	return result, true
}

func (d *downloads) remember(chat string, p tg.InputPeerClass, message *tg.Message, entities peer.Entities) string {
	item, ok := findAttachment(chat, p, message, entities)
	if !ok {
		return ""
	}
	if _, known := d.available[item.ID]; !known && len(d.available) >= 500 {
		var oldest attachment
		for _, candidate := range d.available {
			if d.active != nil && candidate.ID == d.active.id {
				continue
			}
			if oldest.ID == "" || candidate.Date < oldest.Date {
				oldest = candidate
			}
		}
		delete(d.available, oldest.ID)
		delete(d.failed, oldest.ID)
	}
	d.available[item.ID] = item
	return item.Name
}

func (d *downloads) filePath(record fileRecord) string {
	return filepath.Join(d.root, record.ID, "file", record.Name)
}

func (d *downloads) settle() {
	if d.active == nil {
		return
	}
	select {
	case err := <-d.active.done:
		d.finish(err)
	default:
	}
}

func (d *downloads) finish(err error) {
	job := d.active
	job.cancel()
	d.active = nil
	if err == nil {
		d.saved[job.id] = d.available[job.id].fileRecord
	} else if !errors.Is(err, context.Canceled) {
		d.failed[job.id] = err.Error()
	}
}

func (d *downloads) stop() {
	if d.active != nil {
		d.active.cancel()
		d.finish(<-d.active.done)
	}
}

func (d *downloads) rows(chat string) []fileRow {
	result := make([]fileRow, 0)
	for _, record := range d.saved {
		if chat == "" || record.Chat == chat {
			path := url.URL{Scheme: "file", Path: d.filePath(record)}
			result = append(result, fileRow{fileRecord: record, State: "saved", URL: path.String()})
		}
	}
	for id, record := range d.available {
		if _, saved := d.saved[id]; saved || (chat != "" && record.Chat != chat) {
			continue
		}
		row := fileRow{fileRecord: record.fileRecord, State: "available", Error: d.failed[id]}
		if d.active != nil && d.active.id == id {
			row.State, row.Bytes = "downloading", d.active.bytes.Load()
		}
		result = append(result, row)
	}
	priority := map[string]int{"downloading": 0, "saved": 1, "available": 2}
	sort.Slice(result, func(i, j int) bool {
		first, second := result[i], result[j]
		if first.State != second.State {
			return priority[first.State] < priority[second.State]
		}
		if first.Date != second.Date {
			return first.Date > second.Date
		}
		return first.ID < second.ID
	})
	return result
}

func (d *downloads) start(ctx context.Context, client *telegram.Client, id string) error {
	if d.active != nil {
		return errors.New("Wait for the current download or cancel it")
	}
	if _, saved := d.saved[id]; saved {
		return nil
	}
	item, ok := d.available[id]
	if !ok {
		return errors.New("Open the message again to find this file")
	}
	jobContext, cancel := context.WithCancel(ctx)
	job := &download{id: id, cancel: cancel, done: make(chan error, 1)}
	delete(d.failed, id)
	d.active = job
	go func() {
		job.done <- d.save(jobContext, item, &job.bytes, func(ctx context.Context, output io.Writer) error {
			connection, err := client.DC(ctx, item.dc, 1)
			if err != nil {
				return fmt.Errorf("connect to the file: %w", err)
			}
			defer connection.Close()
			_, err = downloader.NewDownloader().Download(tg.NewClient(connection), item.location).
				WithRefresh(fileref.Message(client.API(), item.peer, item.Message, item.location)).Stream(ctx, output)
			return err
		})
	}()
	return nil
}

type countedWriter struct {
	destination io.Writer
	count       *atomic.Int64
}

func (w countedWriter) Write(data []byte) (int, error) {
	n, err := w.destination.Write(data)
	w.count.Add(int64(n))
	return n, err
}

func (d *downloads) save(ctx context.Context, item attachment, count *atomic.Int64, stream func(context.Context, io.Writer) error) error {
	path := d.filePath(item.fileRecord)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	temp, err := os.CreateTemp(filepath.Dir(path), ".partial-")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	streamErr := stream(ctx, countedWriter{temp, count})
	if err := errors.Join(streamErr, temp.Close()); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if item.Size > 0 && count.Load() != item.Size {
		return errors.New("Telegram returned an incomplete file. Try the download again.")
	}
	meta, err := json.Marshal(item.fileRecord)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(d.root, item.ID, "metadata.json"), meta, 0600); err != nil {
		return err
	}
	return os.Rename(temp.Name(), path)
}
