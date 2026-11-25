# Apps for Ubuntu Touch 16.04

Both apps target the `ubuntu-sdk-16.04.8` framework. ChatGPT Web has architecture `all`. Pocket Player 1.1.0 comes in `armhf` and `arm64` builds. Run `dpkg --print-architecture` on the tablet to pick the matching package.

## Pocket Player

A lightweight player for local audio and video. Open **Pocket Player**, tap **Open file**, and choose an audio or video file through Content Hub. You can also send a media file to Pocket Player from File Manager.

Pocket Player tries the Ubuntu Touch media engine first. If a codec fails, Pocket Player prepares a temporary MP4 with H.264 video and/or AAC audio using its bundled FFmpeg engine. You can also tap **Play in compatibility mode** to start that conversion. Compatibility mode scales video to fit within 854 × 480 and plays the converted copy when it is ready. Long files can take time and require free space. The selected file is preserved.

Compatibility samples cover 31 extensions across audio and video, including MP3, WAV, FLAC, AAC, M4A, WMA, OGG, MP4, MKV, AVI, MOV, WebM, WMV, and MPEG. See [the format list](media-engine/README.md) for details.

## ChatGPT Web

A launcher for the official ChatGPT website. Open **ChatGPT Web** and sign in on the site. The launcher uses your device’s Morph web app container. Ubuntu Touch 16.04’s older browser engine may fail to load the site or complete sign-in.

## Install and build

Open each downloaded `.click` in File Manager and select **OpenStore → Install**. Alternatively, use `pkcon install-local --allow-untrusted /path/to/file.click` on the tablet.

To rebuild with compatibility mode, follow the [media engine instructions](media-engine/README.md). With the Click builder on your path, `python3 build.py` builds ChatGPT Web and the original architecture-independent Pocket Player with the system codecs.
