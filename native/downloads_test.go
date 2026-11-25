package main

import (
	"context"
	"errors"
	"io"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"unicode/utf8"

	"github.com/gotd/td/telegram/message/peer"
	"github.com/gotd/td/tg"
)

func TestAttachmentMetadata(t *testing.T) {
	incoming := &tg.Message{ID: 34, Date: 123, PeerID: &tg.PeerChat{ChatID: 4}}
	target := &tg.InputPeerChat{ChatID: 4}
	incoming.Media = &tg.MessageMediaPhoto{Photo: &tg.Photo{DCID: 2, Sizes: []tg.PhotoSizeClass{
		&tg.PhotoSize{Type: "m", Size: 200},
		&tg.PhotoSizeProgressive{Type: "x", Sizes: []int{300, 650}},
	}}}
	item, ok := findAttachment("chat", target, incoming, peer.Entities{})
	if !ok || item.Size != 650 || item.location.(*tg.InputPhotoFileLocation).ThumbSize != "x" {
		t.Fatalf("expected full-size photo, got %+v", item)
	}

	incoming.Media = &tg.MessageMediaDocument{Document: &tg.Document{ID: 9, DCID: 2, MimeType: "audio/mpeg"}}
	item, ok = findAttachment("chat", target, incoming, peer.Entities{})
	if !ok || item.Name != "audio-9.mp3" || item.Kind != "Audio" {
		t.Fatalf("expected MP3 metadata, got %+v", item)
	}
	incoming.Noforwards = true
	if _, ok := findAttachment("chat", target, incoming, peer.Entities{}); ok {
		t.Fatal("protected attachment was offered for download")
	}
	incoming.Noforwards = false
	incoming.Media.(*tg.MessageMediaDocument).TTLSeconds = 5
	if _, ok := findAttachment("chat", target, incoming, peer.Entities{}); ok {
		t.Fatal("expiring attachment was offered for download")
	}
}

func TestSaveReloadAndIsolation(t *testing.T) {
	root := t.TempDir()
	files := openDownloads(root, 10)
	record := fileRecord{ID: "one", Chat: "chat", Name: safeName("../../track.mp3"), Size: 4}
	item := attachment{fileRecord: record}
	var progress atomic.Int64
	stream := func(_ context.Context, writer io.Writer) error {
		_, err := io.WriteString(writer, "data")
		return err
	}
	if err := files.save(context.Background(), item, &progress, stream); err != nil {
		t.Fatal(err)
	}
	if progress.Load() != 4 {
		t.Fatalf("progress was %d, want 4", progress.Load())
	}
	got, err := os.ReadFile(files.filePath(record))
	if err != nil || string(got) != "data" {
		t.Fatalf("saved file is %q (%v)", got, err)
	}
	rows := openDownloads(root, 10).rows("chat")
	if len(rows) != 1 || rows[0].State != "saved" || !strings.HasSuffix(rows[0].URL, "/track.mp3") {
		t.Fatalf("saved file did not reload: %+v", rows)
	}
	if rows := openDownloads(root, 11).rows(""); len(rows) != 0 {
		t.Fatalf("another account saw saved files: %+v", rows)
	}
}

func TestCanceledAndIncompleteDownloads(t *testing.T) {
	d := openDownloads(t.TempDir(), 1)
	for _, canceled := range []bool{false, true} {
		ctx, cancel := context.WithCancel(context.Background())
		if canceled {
			cancel()
		}
		record := fileRecord{ID: "clip", Name: "clip.mp4", Size: 5}
		var progress atomic.Int64
		err := d.save(ctx, attachment{fileRecord: record}, &progress, func(context.Context, io.Writer) error { return nil })
		cancel()
		if err == nil || canceled != errors.Is(err, context.Canceled) {
			t.Fatalf("unexpected outcome for canceled=%v: %v", canceled, err)
		}
		if _, err := os.Stat(d.filePath(record)); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("incomplete file is visible: %v", err)
		}
	}
	name := safeName("..\\/" + strings.Repeat("ı", 120) + "\u202e.mp4")
	if !utf8.ValidString(name) || len(name) > 180 || !strings.HasSuffix(name, ".mp4") || strings.ContainsAny(name, "/\\\u202e") {
		t.Fatalf("unsafe filename: %q", name)
	}
}
