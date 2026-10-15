# LinkDrop for macOS

A simple native Mac video downloader. Paste a URL, choose quality, save a video or MP3. Runs locally using yt-dlp, FFmpeg, and Deno bundled into the app.

## Install

**Recommended:** Download the latest [LinkDrop macOS DMG](../../releases/latest), double-click it, and drag `LinkDrop.app` to the Applications shortcut in the installer window. Eject the installer disk, then open the app from Applications.

The release also includes an ordinary ZIP for alternative installation. Requires macOS 13 or later (Apple Silicon or Intel). No Homebrew, Python, Xcode or Terminal required for normal use.

**Mac security:** The app is ad-hoc signed, **not Apple Developer ID signed or notarized**. The DMG does not remove that restriction; macOS may block it on first launch. On your own trusted download, attempt to launch from Applications, then go to **System Settings → Privacy & Security → Open Anyway** if that option is offered. Apple-notarized, warning-free distribution requires an Apple Developer ID certificate, developer account and notarization. Do **not** disable Gatekeeper system-wide. If macOS says the app is "damaged", treat that separately from "unidentified developer" and report the exact error.

Features: best/1080p/720p/MP3 options, retries, resumable downloads when supported, playlist opt-in, browser-cookie opt-in for videos you may access, download progress, cancel, and an updateable yt-dlp engine. The app has no telemetry or hosted download server.

Not all websites or videos work. DRM, inaccessible/private or paywalled content aren't bypassed. Download only where authorized and respect creators' rights and site policies.

## Developer notes

- App source: `LinkDrop.swift`
- Tool bundling: `scripts/bundle-tools.sh`
- Universal Apple Silicon/Intel build, executable smoke test, signed bundle, installer DMG and release: `.github/workflows/build-macos.yml`
- The DMG is a drag-and-drop installer, **not a privileged installer package**.
- Third-party dependencies are downloaded during the build and checked against upstream SHA-256 manifests; this is not an independent security audit. Dependencies retain their own licenses.
