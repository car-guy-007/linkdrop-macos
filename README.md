# LinkDrop for macOS

A lightweight native Mac video downloader. Paste a URL, choose quality, and download files to a selected folder. Uses yt-dlp, FFmpeg, and Deno in a self-contained application bundle.

**Download the app:** Open [Actions](../../actions/workflows/build-macos.yml), select the latest successful **Build LinkDrop macOS app** run, and download the **LinkDrop-macOS** artifact. Unzip it twice if prompted, then drag `LinkDrop.app` to Applications.

**Important:** Builds are ad-hoc signed rather than Apple Developer ID notarized. macOS may require System Settings → Privacy & Security → Open Anyway on first launch. Always confirm the download came from your repository.

Features: best/1080p/720p/MP3, retries, resume, playlist opt-in, browser-cookie opt-in for content you have access to, download progress and cancellation, updateable yt-dlp engine. No web service or telemetry.

Not all websites or videos work. DRM, inaccessible/private or paywalled content are not bypassed. Respect creators' rights and website terms.

**Developer notes:** Source: `LinkDrop.swift`. Packaging/dependencies: `scripts/bundle-tools.sh`. Automated universal Apple Silicon + Intel build: `.github/workflows/build-macos.yml`. Dependencies are retrieved from their upstream publishers at build time and SHA-256 checked against their corresponding release manifests. The integrity checks do not constitute an independent security audit. Third-party tools are distributed under their own licenses.
