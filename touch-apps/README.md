# Apps for Ubuntu Touch 16.04

Both apps target the `ubuntu-sdk-16.04.8` framework. ChatGPT Web has architecture `all`. Pocket Player 1.2.1 comes in `armhf` and `arm64` builds. Run `dpkg --print-architecture` on the tablet to pick the matching package.

## Pocket Player

A lightweight player for local audio and video. Open **Pocket Player**, tap **Open file**, and choose an audio or video file through Content Hub. You can also send a media file to Pocket Player from File Manager.

Pocket Player tries the Ubuntu Touch media engine first. If a codec fails, compatibility mode uses the bundled FFmpeg engine to convert the media to H.264 video and/or AAC audio, scaling video to fit within 854 × 480. You can also start it with **Play in compatibility mode**.

Pocket Player can receive an MKV from File Manager even if it is classified as a generic file. When native MKV playback starts with audio but no video, Pocket Player retries with the compatibility engine.

Compatibility mode streams files of 64 MiB and larger to the player as they convert. This starts playback without preparing a full file on disk. The streamed version plays sequentially. If the system player rejects the stream, tap **Prepare a full copy** to use the disk-based fallback. File Manager may still need time to transfer large imports through Content Hub.

Compatibility samples cover 31 extensions across audio and video, including MP3, WAV, FLAC, AAC, M4A, WMA, OGG, MP4, MKV, AVI, MOV, WebM, WMV, and MPEG. See [the format list](media-engine/README.md) for details.

## ChatGPT Web

A launcher for the official ChatGPT website. Open **ChatGPT Web** and sign in on the site. The launcher uses your device’s Morph web app container. Ubuntu Touch 16.04’s older browser engine may fail to load the site or complete sign-in.

## Install and build

Open each downloaded `.click` in File Manager and select **OpenStore → Install**. Alternatively, use `pkcon install-local --allow-untrusted /path/to/file.click` on the tablet.

To rebuild with compatibility mode, follow the [media engine instructions](media-engine/README.md). With the Click builder on your path, `python3 build.py` builds ChatGPT Web and the original architecture-independent Pocket Player with the system codecs.
