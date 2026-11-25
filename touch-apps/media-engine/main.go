package main

import (
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
	"sync"
	"syscall"
	"time"
)

type command struct {
	Action string `json:"action"`
	Source string `json:"source"`
}

type status struct {
	State string `json:"state"`
	URL   string `json:"url,omitempty"`
	Error string `json:"error,omitempty"`
}

type converter struct {
	mu     sync.Mutex
	ctx    context.Context
	ffmpeg string
	dir    string
	state  status
	cancel context.CancelFunc
	done   chan struct{}
}

func localFile(value string) (string, error) {
	uri, err := url.Parse(value)
	if err != nil || uri.Scheme != "file" || uri.Host != "" || uri.User != nil ||
		uri.RawQuery != "" || uri.Fragment != "" || !filepath.IsAbs(uri.Path) {
		return "", errors.New("Choose a local file")
	}
	info, err := os.Stat(uri.Path)
	if err != nil || !info.Mode().IsRegular() {
		return "", errors.New("The selected file could not be read")
	}
	return uri.Path, nil
}

func conversionArgs(source, output string) []string {
	return []string{
		"-nostdin", "-hide_banner", "-loglevel", "error", "-y",
		"-protocol_whitelist", "file", "-max_alloc", "134217728",
		"-threads", "2", "-i", source,
		"-map", "0:V:0?", "-map", "0:a:0?", "-map_metadata", "-1", "-map_chapters", "-1",
		"-filter_threads", "1",
		"-vf", "scale=w='min(854,iw)':h='min(480,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
		"-r", "24", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "26",
		"-pix_fmt", "yuv420p", "-threads", "2",
		"-c:a", "aac", "-b:a", "96k", "-ac", "2", "-ar", "44100",
		"-movflags", "+faststart", output,
	}
}

func (c *converter) start(source string) error {
	if c.cancel != nil {
		return errors.New("Wait for the current conversion to finish or cancel it")
	}
	input, err := localFile(source)
	if err != nil {
		return err
	}
	output := filepath.Join(c.dir, "compatible.mp4")
	if err := os.Remove(output); err != nil && !errors.Is(err, os.ErrNotExist) {
		return errors.New("The previous temporary file could not be removed")
	}
	ctx, cancel := context.WithCancel(c.ctx)
	done := make(chan struct{})
	c.cancel, c.done, c.state = cancel, done, status{State: "working"}

	go func() {
		defer close(done)
		runErr := exec.CommandContext(ctx, c.ffmpeg, conversionArgs(input, output)...).Run()
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

func (c *converter) handle(token string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
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
		case "start":
			err = c.start(cmd.Source)
		case "cancel":
			if c.cancel != nil {
				c.cancel()
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

	c := &converter{ctx: ctx, ffmpeg: filepath.Join(appPath, "ffmpeg"), dir: cache, state: status{State: "idle"}}
	server := &http.Server{Handler: c.handle(token), ReadHeaderTimeout: 3 * time.Second, ReadTimeout: 5 * time.Second, WriteTimeout: 5 * time.Second, IdleTimeout: 10 * time.Second}
	go func() { _ = server.Serve(listener) }()

	ui := exec.CommandContext(ctx, "qmlscene", "--pocket-config="+config, filepath.Join(appPath, "PocketPlayer.qml"))
	ui.Env = append(os.Environ(), "QML_XHR_ALLOW_FILE_READ=1")
	ui.Stderr = os.Stderr
	launchErr := ui.Run()

	shutdown, finish := context.WithTimeout(context.Background(), 6*time.Second)
	_ = server.Shutdown(shutdown)
	finish()
	stop()
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
