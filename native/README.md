# Sparrow Chat

Sparrow Chat is an unofficial native Telegram client for Ubuntu Touch 16.04. Its interface uses Qt Quick and Ubuntu Components. The bundled Go backend connects directly to Telegram using [gotd](https://github.com/gotd/td).

The first build supports signing in to an existing account, two-step verification, the 50 most recent chats, message history, and sending plain text. It refreshes the current screen while active and shows attachment placeholders. It does not download media or provide background notifications, calls, secret chats, or account registration.

## Install

Run `dpkg --print-architecture` in Terminal on the phone and pick the matching `.click`. Supported phones have the `ubuntu-sdk-16.04.8` framework. Open the package in File Manager and select OpenStore, or run `pkcon install-local --allow-untrusted /path/to/package.click`.

Open **Sparrow Chat** and enter the API ID and API hash from **API development tools** at [my.telegram.org](https://my.telegram.org). Enter the phone number and the verification code Telegram sends. If Telegram prompts for two-step verification, enter the account password on the device. The app saves the API credentials and session in its private local data directory. Never share the session file or API hash.

## Build

Install Go 1.25 or later and the `click` package builder. Run `python3 build.py armhf` or `python3 build.py arm64` to create a package under `dist`. You can also build for `amd64`. The Ubuntu Touch image supplies Qt Quick, Ubuntu Components, and qmlscene. The bundled backend communicates with the interface over a local connection using a randomly generated token.

This is an early build. Successful Telegram sign-in and operation on a physical Ubuntu Touch device have not been verified.
