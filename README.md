# Telegram Web for Ubuntu Touch

This unofficial wrapper opens [Telegram Web K](https://web.telegram.org/k/) in its own app using Ubuntu Touch’s Morph web app container. Sign-in takes place on Telegram’s site. Morph keeps the wrapper’s browsing data in its own profile.

## Sparrow Chat for Ubuntu Touch 16.04

Sparrow Chat is a lightweight native Telegram client. The preview release has a Downloads tab and installable `armhf` and `arm64` builds. [Download Sparrow Chat 0.2.0](https://github.com/UndrDsk0M/Telegram-wrapper-ubuntutouch/releases/tag/sparrow-v0.2.0)

## Pocket Player and ChatGPT Web for Ubuntu Touch 16.04

Pocket Player 1.1.0 supports 31 tested audio and video file types. ChatGPT Web opens the official ChatGPT website. [Download both apps](https://github.com/UndrDsk0M/Telegram-wrapper-ubuntutouch/releases/tag/touch-apps-v1.1.0)

## Beacon Holdout for Ubuntu Touch 16.04

An offline touchscreen zombie game with five waves in an original wartime bunker. [Download Beacon Holdout 0.1.0](https://github.com/UndrDsk0M/Telegram-wrapper-ubuntutouch/releases/tag/beacon-v0.1.0)

## Install

Check the Ubuntu Touch release in **Settings → About** and choose its matching `.click` file. The `all` package works across CPU architectures. Open the downloaded file in File Manager, choose **OpenStore**, and tap **Install**. Launch **Telegram Web** from the app drawer.

Messaging and sign-in depend on Telegram Web and the device’s version of Morph. The 16.04 package targets the `ubuntu-sdk-16.04.8` framework. Its older browser engine may have trouble running Telegram Web. The wrapper does not implement native push notifications. Phone installation and sign-in have not been tested.

## Build from source

Run `python3 build.py` with the Ubuntu Touch Click package builder (`click`) on `PATH`. The packages go to `dist/` by default. To build only one release, pass `16.04`, `20.04`, `24.04-1.x`, or `24.04-2.x`. For example, run `python3 build.py 16.04`.
