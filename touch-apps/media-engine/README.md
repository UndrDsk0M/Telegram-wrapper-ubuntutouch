# Pocket Player 1.2.1 media compatibility

The compatibility engine processes one selected local file at a time. Files smaller than 64 MiB are prepared as a seekable temporary MP4. Larger files are converted to a fragmented MP4 stream while they play. The app binds the playback service to localhost and uses a randomly generated URL for each stream. The stream plays sequentially. The engine converts the first video track (excluding cover art) and the first audio track, scaling video to fit within 854 × 480. Original media files are preserved.

## Tested file types

- Audio: AAC, AC3, AIFF, AU, CAF, EAC3, FLAC, M4A (ALAC), MKA (FLAC), MP2, MP3, OGG (Vorbis), Opus, TTA, WAV, WMA, WV (WavPack).
- Video: 3GP, AVI, FLV, M4V, MKV (H.265), MOV, MP4 (H.264), MPG, OGV, RM, TS, VOB, WebM (VP9), WMV.

The test set uses a sample of each file type. Codec variants within a container can differ. Subtitle rendering, DRM-protected files, and DVD menus are outside the compatibility workflow.

## Build

Install Zig 0.14.1, Go 1.25, make, pkg-config, and the Click package builder. Extract FFmpeg 8.1.2 and x264 revision 0480cb0. The corresponding source archive contains the exact upstream archives. From the project root:

```sh
mkdir -p codecs
media-engine/build-codecs.sh armhf /path/to/zig /path/to/ffmpeg-8.1.2 /path/to/x264 codecs/ffmpeg-armhf
media-engine/build-codecs.sh arm64 /path/to/zig /path/to/ffmpeg-8.1.2 /path/to/x264 codecs/ffmpeg-arm64
python3 build.py --player-codecs-dir codecs
```

FFmpeg and x264 run as a separate executable under GPL version 2 or later. The build uses the musl and compiler runtime shipped with [Zig 0.14.1](https://ziglang.org/download/0.14.1/zig-0.14.1.tar.xz). License notices are included in each package.
