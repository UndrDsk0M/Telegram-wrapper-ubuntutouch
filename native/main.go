package main

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf16"

	"github.com/gotd/td/session"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/telegram/message/peer"
	"github.com/gotd/td/telegram/query/dialogs"
	"github.com/gotd/td/telegram/query/messages"
	"github.com/gotd/td/tg"
)

const pageSize = 30

type credentials struct {
	ID   int    `json:"id"`
	Hash string `json:"hash"`
}

type request struct {
	Action string `json:"action"`
	ID     string `json:"id"`
	Hash   string `json:"hash"`
	Value  string `json:"value"`
	Chat   string `json:"chat"`
	Before int    `json:"before"`
	Read   bool   `json:"read"`
}

type row struct {
	Key    string `json:"key"`
	Title  string `json:"title"`
	Text   string `json:"text"`
	Unread int    `json:"unread"`
}

type entry struct {
	ID         int    `json:"id"`
	Sender     string `json:"sender"`
	Text       string `json:"text"`
	Time       int    `json:"time"`
	Mine       bool   `json:"mine"`
	Attachment string `json:"attachment,omitempty"`
}

type reply struct {
	Stage       string    `json:"stage"`
	Error       string    `json:"error,omitempty"`
	Chats       []row     `json:"chats"`
	Messages    []entry   `json:"messages"`
	Files       []fileRow `json:"files"`
	Downloading bool      `json:"downloading"`
}

type app struct {
	dir      string
	stage    string
	phone    string
	codeHash string
	client   *telegram.Client
	ctx      context.Context
	cancel   context.CancelFunc
	done     <-chan error
	chats    map[string]tg.InputPeerClass
	read     map[string]int
	files    *downloads
}

func (a *app) stop() {
	if a.files != nil {
		a.files.stop()
		a.files = nil
	}
	if a.cancel != nil {
		a.cancel()
		<-a.done
		a.cancel = nil
		a.client = nil
	}
}

func (a *app) connect(creds credentials) error {
	a.stop()
	a.stage = "connect"
	a.read = make(map[string]int)
	lifetime, cancel := context.WithCancel(context.Background())
	client := telegram.NewClient(creds.ID, creds.Hash, telegram.Options{
		NoUpdates:      true,
		SessionStorage: &session.FileStorage{Path: filepath.Join(a.dir, "session.json")},
		Device: telegram.DeviceConfig{
			DeviceModel: "Ubuntu Touch", SystemVersion: "16.04", AppVersion: "0.2.0",
			SystemLangCode: "en", LangCode: "en",
		},
	})
	ready := make(chan context.Context, 1)
	done := make(chan error, 1)
	go func() {
		done <- client.Run(lifetime, func(ctx context.Context) error {
			ready <- ctx
			<-ctx.Done()
			return nil
		})
	}()
	timer := time.NewTimer(18 * time.Second)
	defer timer.Stop()
	select {
	case ctx := <-ready:
		a.client, a.ctx, a.cancel, a.done = client, ctx, cancel, done
	case err := <-done:
		cancel()
		if err == nil {
			return errors.New("Telegram connection closed")
		}
		return err
	case <-timer.C:
		cancel()
		<-done
		return errors.New("Telegram did not respond. Check your internet connection and retry.")
	}

	ctx, closeRequest := context.WithTimeout(a.ctx, 12*time.Second)
	defer closeRequest()
	status, err := a.client.Auth().Status(ctx)
	if err != nil {
		a.stop()
		return err
	}
	a.stage = "phone"
	if status.Authorized {
		return a.openAccount(status.User)
	}
	return nil
}

func (a *app) openAccount(account tg.UserClass) error {
	user, ok := account.(*tg.User)
	if !ok || user == nil {
		a.stage = "connect"
		return errors.New("Telegram did not return account information. Tap Retry.")
	}
	a.files = openDownloads(a.dir, user.ID)
	a.stage = "chats"
	a.phone, a.codeHash = "", ""
	return nil
}

func (a *app) configure(req request) error {
	id, err := strconv.ParseInt(strings.TrimSpace(req.ID), 10, 32)
	hash := strings.TrimSpace(req.Hash)
	_, hashError := hex.DecodeString(hash)
	if err != nil || id <= 0 || len(hash) != 32 || hashError != nil {
		return errors.New("Enter a valid API ID and 32-character API hash")
	}
	creds := credentials{ID: int(id), Hash: hash}
	data, err := json.Marshal(creds)
	if err != nil {
		return err
	}
	config := filepath.Join(a.dir, "credentials.json")
	if err := os.WriteFile(config+".tmp", data, 0600); err != nil {
		return err
	}
	if err := os.Rename(config+".tmp", config); err != nil {
		return err
	}
	return a.connect(creds)
}

func (a *app) start() error {
	data, err := os.ReadFile(filepath.Join(a.dir, "credentials.json"))
	if errors.Is(err, os.ErrNotExist) {
		a.stage = "setup"
		return nil
	}
	if err != nil {
		return err
	}
	var creds credentials
	if err := json.Unmarshal(data, &creds); err != nil {
		a.stage = "setup"
		return errors.New("Enter your Telegram API credentials again")
	}
	return a.connect(creds)
}

func (a *app) authenticate(ctx context.Context, value string) error {
	if strings.TrimSpace(value) == "" {
		return errors.New("Enter a value to continue")
	}
	switch a.stage {
	case "phone":
		phone := strings.TrimSpace(value)
		sent, err := a.client.Auth().SendCode(ctx, phone, auth.SendCodeOptions{})
		if err != nil {
			return err
		}
		switch result := sent.(type) {
		case *tg.AuthSentCode:
			a.phone, a.codeHash, a.stage = phone, result.PhoneCodeHash, "code"
		case *tg.AuthSentCodeSuccess:
			signedIn, ok := result.Authorization.(*tg.AuthAuthorization)
			if !ok {
				return errors.New("Create your account with Telegram before signing in here")
			}
			return a.openAccount(signedIn.User)
		default:
			return errors.New("This Telegram sign-in method is unavailable in the client")
		}
	case "code":
		signedIn, err := a.client.Auth().SignIn(ctx, a.phone, strings.TrimSpace(value), a.codeHash)
		if errors.Is(err, auth.ErrPasswordAuthNeeded) {
			a.stage = "password"
			return nil
		}
		if err != nil {
			return err
		}
		return a.openAccount(signedIn.User)
	case "password":
		signedIn, err := a.client.Auth().Password(ctx, value)
		if err != nil {
			return err
		}
		return a.openAccount(signedIn.User)
	default:
		return errors.New("Sign-in is unavailable in this screen")
	}
	return nil
}

func name(person tg.PeerClass, entities peer.Entities) string {
	switch p := person.(type) {
	case *tg.PeerUser:
		if user := entities.Users()[p.UserID]; user != nil {
			if user.Self {
				return "Saved messages"
			}
			if full := strings.TrimSpace(user.FirstName + " " + user.LastName); full != "" {
				return full
			}
		}
	case *tg.PeerChat:
		if chat := entities.Chats()[p.ChatID]; chat != nil {
			return chat.Title
		}
	case *tg.PeerChannel:
		if channel := entities.Channels()[p.ChannelID]; channel != nil {
			return channel.Title
		}
	}
	return "Telegram chat"
}

func messageText(value tg.NotEmptyMessage) string {
	if message, ok := value.(*tg.Message); ok {
		if message.Message != "" {
			return message.Message
		}
		if message.Media != nil {
			return "[Attachment]"
		}
	}
	if value != nil {
		return "[Chat activity]"
	}
	return ""
}

func (a *app) list(ctx context.Context) ([]row, error) {
	iter := dialogs.NewQueryBuilder(a.client.API()).GetDialogs().BatchSize(50).Iter()
	result := make([]row, 0, 50)
	peers := make(map[string]tg.InputPeerClass)
	for len(result) < 50 && iter.Next(ctx) {
		value := iter.Value()
		dialog, ok := value.Dialog.(*tg.Dialog)
		if !ok {
			continue
		}
		if _, empty := value.Peer.(*tg.InputPeerEmpty); empty {
			continue
		}
		key := fmt.Sprintf("%T-%v", value.Peer, dialog.Peer)
		preview := messageText(value.Last)
		if message, ok := value.Last.(*tg.Message); ok {
			filename := a.files.remember(key, value.Peer, message, value.Entities)
			if filename != "" && message.Message == "" {
				preview = filename
			}
		}
		result = append(result, row{key, name(dialog.Peer, value.Entities), preview, dialog.UnreadCount})
		peers[key] = value.Peer
	}
	if err := iter.Err(); err != nil {
		return nil, err
	}
	a.chats = peers
	return result, nil
}

func (a *app) history(ctx context.Context, p tg.InputPeerClass, key string, before int) ([]entry, error) {
	iter := messages.NewQueryBuilder(a.client.API()).GetHistory(p).OffsetID(before).BatchSize(pageSize).Iter()
	result := make([]entry, 0, pageSize)
	for len(result) < pageSize && iter.Next(ctx) {
		value := iter.Value()
		message := value.Msg
		item := entry{ID: message.GetID(), Time: message.GetDate(), Text: messageText(message)}
		if text, ok := message.(*tg.Message); ok {
			item.Mine = text.Out
			item.Attachment = a.files.remember(key, p, text, value.Entities)
			if item.Attachment != "" {
				item.Text = text.Message
			}
			if sender, exists := text.GetFromID(); exists && !text.Out {
				item.Sender = name(sender, value.Entities)
			}
		}
		result = append(result, item)
	}
	if err := iter.Err(); err != nil {
		return nil, err
	}
	for first, last := 0, len(result)-1; first < last; first, last = first+1, last-1 {
		result[first], result[last] = result[last], result[first]
	}
	return result, nil
}

func (a *app) markRead(ctx context.Context, key string, p tg.InputPeerClass, id int) {
	if a.read[key] >= id {
		return
	}
	var err error
	if channel, ok := p.(*tg.InputPeerChannel); ok {
		_, err = a.client.API().ChannelsReadHistory(ctx, &tg.ChannelsReadHistoryRequest{
			Channel: &tg.InputChannel{ChannelID: channel.ChannelID, AccessHash: channel.AccessHash},
			MaxID:   id,
		})
	} else {
		_, err = a.client.API().MessagesReadHistory(ctx, &tg.MessagesReadHistoryRequest{Peer: p, MaxID: id})
	}
	if err == nil {
		a.read[key] = id
	}
}

func (a *app) command(req request, result *reply) error {
	switch req.Action {
	case "start":
		return a.start()
	case "configure":
		return a.configure(req)
	case "setup":
		a.stop()
		a.stage = "setup"
		return nil
	case "restart-sign-in":
		if a.stage == "code" || a.stage == "password" {
			a.phone, a.codeHash, a.stage = "", "", "phone"
		}
		return nil
	}
	if a.client == nil {
		return errors.New("Connect to Telegram first")
	}

	ctx, cancel := context.WithTimeout(a.ctx, 15*time.Second)
	defer cancel()
	if req.Action == "auth" {
		return a.authenticate(ctx, req.Value)
	}
	if a.stage != "chats" {
		return errors.New("Sign in before opening chats")
	}
	a.files.settle()
	switch req.Action {
	case "downloads", "download", "cancel-download":
		var err error
		if req.Action == "download" {
			err = a.files.start(a.ctx, a.client, req.Value)
		}
		if req.Action == "cancel-download" && a.files.active != nil && a.files.active.id == req.Value {
			a.files.active.cancel()
		}
		result.Files, result.Downloading = a.files.rows(req.Chat), a.files.active != nil
		return err
	}
	if req.Action == "list" {
		var err error
		result.Chats, err = a.list(ctx)
		return err
	}
	if req.Action == "logout" {
		if _, err := a.client.API().AuthLogOut(ctx); err != nil {
			return err
		}
		a.stop()
		a.chats = nil
		a.stage = "connect"
		if err := os.Remove(filepath.Join(a.dir, "session.json")); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		return nil
	}

	p := a.chats[req.Chat]
	if p == nil {
		return errors.New("Refresh the chat list and try again")
	}
	switch req.Action {
	case "history":
		var err error
		result.Messages, err = a.history(ctx, p, req.Chat, req.Before)
		if err == nil && req.Read && req.Before == 0 && len(result.Messages) > 0 {
			a.markRead(ctx, req.Chat, p, result.Messages[len(result.Messages)-1].ID)
		}
		return err
	case "send":
		text := strings.TrimSpace(req.Value)
		if text == "" || len(utf16.Encode([]rune(text))) > 4096 {
			return errors.New("Enter a message of up to 4,096 characters")
		}
		var id int64
		if err := binary.Read(rand.Reader, binary.LittleEndian, &id); err != nil {
			return err
		}
		_, err := a.client.API().MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
			Peer: p, Message: text, RandomID: id, NoWebpage: true,
		})
		return err
	default:
		return errors.New("Unknown command")
	}
}

func (a *app) handler(token string) http.HandlerFunc {
	var lock sync.Mutex
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/command" || r.Method != http.MethodPost {
			http.NotFound(w, r)
			return
		}
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), []byte("Bearer "+token)) != 1 {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		var req request
		body := http.MaxBytesReader(w, r.Body, 96*1024)
		if err := json.NewDecoder(body).Decode(&req); err != nil {
			http.Error(w, "Invalid request", http.StatusBadRequest)
			return
		}

		lock.Lock()
		defer lock.Unlock()
		var result reply
		if err := a.command(req, &result); err != nil {
			result.Error = err.Error()
			if a.client != nil && a.ctx.Err() != nil {
				a.stop()
				a.stage = "connect"
			}
		}
		result.Stage = a.stage
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(result)
	}
}

func run() error {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	data := os.Getenv("XDG_DATA_HOME")
	if data == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		data = filepath.Join(home, ".local", "share")
	}
	a := &app{dir: filepath.Join(data, "sparrow-chat.touchwrapper"), stage: "connect"}
	if err := os.MkdirAll(a.dir, 0700); err != nil {
		return err
	}
	defer a.stop()

	var secret [32]byte
	if _, err := rand.Read(secret[:]); err != nil {
		return err
	}
	token := hex.EncodeToString(secret[:])
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return err
	}
	defer listener.Close()
	config, err := os.CreateTemp(a.dir, "connection-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(config.Name())
	descriptor := struct {
		Port  int    `json:"port"`
		Token string `json:"token"`
	}{Port: listener.Addr().(*net.TCPAddr).Port, Token: token}
	writeErr := json.NewEncoder(config).Encode(descriptor)
	closeErr := config.Close()
	if err := errors.Join(writeErr, closeErr); err != nil {
		return err
	}

	server := &http.Server{
		Handler: a.handler(token), ReadHeaderTimeout: 3 * time.Second,
		ReadTimeout: 5 * time.Second, WriteTimeout: 40 * time.Second, IdleTimeout: 25 * time.Second,
	}
	go func() { _ = server.Serve(listener) }()
	ui := exec.CommandContext(ctx, "qmlscene", "--sparrow-config="+config.Name(), filepath.Join(filepath.Dir(executable), "Main.qml"))
	ui.Env = append(os.Environ(), "QML_XHR_ALLOW_FILE_READ=1")
	ui.Stderr = os.Stderr
	launchErr := ui.Run()
	shutdown, stop := context.WithTimeout(context.Background(), 42*time.Second)
	defer stop()
	_ = server.Shutdown(shutdown)
	return launchErr
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "Sparrow Chat could not start:", err)
		os.Exit(1)
	}
}
