package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type command struct {
	Action string `json:"action"`
	Source string `json:"source"`
}

type status struct {
	State     string `json:"state"`
	URL       string `json:"url,omitempty"`
	Error     string `json:"error,omitempty"`
	Streaming bool   `json:"streaming,omitempty"`
}

const streamThreshold = 64 * 1024 * 1024

type mediaStream struct {
	path, input string
	ctx         context.Context
	cancel      context.CancelFunc
	busy        bool
}

type converter struct {
	mu      sync.Mutex
	ctx     context.Context
	ffmpeg  string
	dir     string
	state   status
	cancel  context.CancelFunc
	done    chan struct{}
	address string
	stream  *mediaStream
}

func localFile(value string) (string, int64, error) {
	uri, err := url.Parse(value)
	if err != nil || uri.Scheme != "file" || uri.Host != "" || uri.User != nil ||
		uri.RawQuery != "" || uri.Fragment != "" || !filepath.IsAbs(uri.Path) {
		return "", 0, errors.New("Choose a local file")
	}
	info, err := os.Stat(uri.Path)
	if err != nil || !info.Mode().IsRegular() {
		return "", 0, errors.New("The selected file could not be read")
	}
	return uri.Path, info.Size(), nil
}

func conversionArgs(source, output string, stream bool) []string {
	args := []string{
		"-nostdin", "-hide_banner", "-loglevel", "error", "-y",
		"-protocol_whitelist", "file", "-max_alloc", "134217728",
		"-threads", "2", "-i", source,
		"-map", "0:V:0?", "-map", "0:a:0?", "-map_metadata", "-1", "-map_chapters", "-1",
		"-filter_threads", "1",
		"-vf", "scale=w='min(854,iw)':h='min(480,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
		"-r", "24", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "26",
		"-pix_fmt", "yuv420p", "-threads", "2",
		"-c:a", "aac", "-b:a", "96k", "-ac", "2", "-ar", "44100",
	}
	if stream {
		return append(args, "-movflags", "+empty_moov+default_base_moof+frag_keyframe",
			"-frag_duration", "1000000", "-flush_packets", "1", "-f", "mp4", "pipe:1")
	}
	return append(args, "-movflags", "+faststart", output)
}

func (c *converter) start(source string, prepareCopy bool) error {
	if c.cancel != nil {
		return errors.New("Wait for the current conversion to finish or cancel it")
	}
	input, size, err := localFile(source)
	if err != nil {
		return err
	}
	output := filepath.Join(c.dir, "compatible.mp4")
	if err := os.Remove(output); err != nil && !errors.Is(err, os.ErrNotExist) {
		return errors.New("The previous temporary file could not be removed")
	}
	if c.stream != nil {
		c.stream.cancel()
		c.stream = nil
	}
	if size >= streamThreshold && !prepareCopy {
		var id [24]byte
		if _, err := rand.Read(id[:]); err != nil {
			return err
		}
		path := "/play/" + hex.EncodeToString(id[:]) + ".mp4"
		ctx, cancel := context.WithCancel(c.ctx)
		c.stream = &mediaStream{path: path, input: input, ctx: ctx, cancel: cancel}
		c.state = status{State: "ready", URL: "http://" + c.address + path, Streaming: true}
		return nil
	}
	ctx, cancel := context.WithCancel(c.ctx)
	done := make(chan struct{})
	c.cancel, c.done, c.state = cancel, done, status{State: "working"}

	go func() {
		defer close(done)
		runErr := exec.CommandContext(ctx, c.ffmpeg, conversionArgs(input, output, false)...).Run()
		c.mu.Lock()
		defer c.mu.Unlock()
		c.cancel = nil
		switch {
		case ctx.Err() != nil:
			c.state = status{State: "idle"}
			_ = os.Remove(output)
		case runErr != nil:
			c.state = status{State: "failed", Error: "This file could not be converted. Check the file and available storage."}
			_ = os.Remove(output)
		default:
			uri := url.URL{Scheme: "file", Path: output}
			c.state = status{State: "ready", URL: uri.String()}
		}
		cancel()
	}()
	return nil
}

func (c *converter) play(w http.ResponseWriter, r *http.Request) {
	c.mu.Lock()
	stream := c.stream
	if stream == nil || subtle.ConstantTimeCompare([]byte(stream.path), []byte(r.URL.Path)) != 1 ||
		(r.Method != http.MethodGet && r.Method != http.MethodHead) {
		c.mu.Unlock()
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "video/mp4")
	w.Header().Set("Accept-Ranges", "none")
	w.Header().Set("Cache-Control", "no-store")
	if r.Method == http.MethodHead {
		c.mu.Unlock()
		return
	}
	if stream.busy {
		c.mu.Unlock()
		http.Error(w, "Playback is already active", http.StatusConflict)
		return
	}
	w.Header().Set("Connection", "close")
	stream.busy = true
	c.mu.Unlock()
	defer func() {
		c.mu.Lock()
		stream.busy = false
		c.mu.Unlock()
	}()

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	stop := context.AfterFunc(stream.ctx, cancel)
	defer stop()
	command := exec.CommandContext(ctx, c.ffmpeg, conversionArgs(stream.input, "", true)...)
	output, err := command.StdoutPipe()
	if err != nil || command.Start() != nil {
		http.Error(w, "Playback could not start", http.StatusUnprocessableEntity)
		return
	}
	defer func() {
		cancel()
		_ = command.Wait()
	}()
	reader := bufio.NewReaderSize(output, 32*1024)
	if _, err := reader.Peek(1); err != nil {
		http.Error(w, "The media stream could not be decoded", http.StatusUnprocessableEntity)
		return
	}
	controller := http.NewResponseController(w)
	interruptWrites := context.AfterFunc(ctx, func() {
		_ = controller.SetWriteDeadline(time.Now())
	})
	defer interruptWrites()
	buffer := make([]byte, 32*1024)
	for {
		n, err := reader.Read(buffer)
		if n > 0 {
			if _, err := w.Write(buffer[:n]); err != nil || controller.Flush() != nil {
				return
			}
		}
		if err != nil {
			return
		}
	}
}

func (c *converter) handle(token string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/conversion" {
			c.play(w, r)
			return
		}
		if r.URL.Path != "/conversion" || r.Method != http.MethodPost {
			http.NotFound(w, r)
			return
		}
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), []byte("Bearer "+token)) != 1 {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		var cmd command
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 32*1024)).Decode(&cmd); err != nil {
			http.Error(w, "Invalid request", http.StatusBadRequest)
			return
		}
		c.mu.Lock()
		defer c.mu.Unlock()
		var err error
		switch cmd.Action {
		case "start", "prepare-copy":
			err = c.start(cmd.Source, cmd.Action == "prepare-copy")
		case "cancel":
			if c.cancel != nil {
				c.cancel()
			}
			if c.stream != nil {
				c.stream.cancel()
				c.stream = nil
				c.state = status{State: "idle"}
			}
		case "status":
		default:
			http.Error(w, "Invalid request", http.StatusBadRequest)
			return
		}
		result := c.state
		if err != nil {
			result = status{State: "failed", Error: err.Error()}
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(result)
	}
}

func playerEnvironment() []string {
	var environment []string
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		switch strings.ToLower(key) {
		case "http_proxy", "https_proxy", "all_proxy":
			// The media player only opens local files and the private loopback stream.
			continue
		}
		environment = append(environment, entry)
	}
	return append(environment, "QML_XHR_ALLOW_FILE_READ=1", "GIO_USE_PROXY_RESOLVER=dummy")
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	appPath := filepath.Dir(executable)
	cache, err := os.UserCacheDir()
	if err != nil {
		return err
	}
	cache = filepath.Join(cache, "pocket-player.touchapps")
	if err := os.MkdirAll(cache, 0700); err != nil {
		return err
	}
	cache, err = os.MkdirTemp(cache, "player-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(cache)

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
	config := filepath.Join(cache, "connection.json")
	descriptor, err := json.Marshal(map[string]any{"port": listener.Addr().(*net.TCPAddr).Port, "token": token})
	if err != nil {
		return err
	}
	if err := os.WriteFile(config, descriptor, 0600); err != nil {
		return err
	}

	c := &converter{ctx: ctx, ffmpeg: filepath.Join(appPath, "ffmpeg"), dir: cache, address: listener.Addr().String(), state: status{State: "idle"}}
	server := &http.Server{Handler: c.handle(token), ReadHeaderTimeout: 3 * time.Second, ReadTimeout: 5 * time.Second, IdleTimeout: 10 * time.Second}
	go func() { _ = server.Serve(listener) }()

	ui := exec.CommandContext(ctx, "qmlscene", "--pocket-config="+config, filepath.Join(appPath, "PocketPlayer.qml"))
	ui.Env = playerEnvironment()
	ui.Stderr = os.Stderr
	launchErr := ui.Run()

	stop()
	shutdown, finish := context.WithTimeout(context.Background(), 6*time.Second)
	_ = server.Shutdown(shutdown)
	finish()
	c.mu.Lock()
	done := c.done
	c.mu.Unlock()
	if done != nil {
		<-done
	}
	return launchErr
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "Pocket Player could not start:", err)
		os.Exit(1)
	}
}
