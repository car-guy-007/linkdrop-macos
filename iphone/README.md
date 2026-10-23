# LinkDrop for iPhone

Installable Safari Home Screen web app (PWA), independent from the existing LinkDrop Mac app.

## Publish it once

1. Open https://github.com/car-guy-007/linkdrop-macos/settings/pages
2. Under **Build and deployment → Source**, select **GitHub Actions**.
3. Open https://github.com/car-guy-007/linkdrop-macos/actions/workflows/iphone-pages.yml
4. Choose **Run workflow** (main) to publish the site now.
5. Once the deployment is green, open https://car-guy-007.github.io/linkdrop-macos/ **in iPhone Safari**.
6. Tap **Share → Add to Home Screen → Open as Web App → Add**. It will appear as **LinkDrop**.

No Xcode, sideloading, Apple developer membership, or code signing is needed.

## What works

The iPhone app checks pasted HTTP(S) links and lets Safari attempt saving a *direct media file* (e.g., MP4, MOV, WebM, MP3). The originating site controls whether the browser downloads, plays, or blocks the media. On iPhone, the user may need to use **Share → Save to Files** or Safari's Downloads interface.

The interface works offline once installed and cached, but downloading requires internet. Recent links are saved in the browser's local storage, on the user's device.

**Limitations:** Ordinary YouTube, Instagram, TikTok, X, Facebook, and other site *page URLs* are not direct video files. GitHub Pages is static hosting; it does not execute yt-dlp or other server-side download engines. Supporting those sites on iPhone requires a separate remote backend with bandwidth/storage and likely recurring hosting costs. No website compatibility, third-party cookies, login sessions, or DRM bypass is promised. Respect copyright and site restrictions.

## Files

- index.html: interface
- style.css: mobile design
- app.js: link classification, download/open links, local history
- sw.js: cache only same-origin app shell, **never third-party video URLs**
- manifest.webmanifest: install metadata
- icon.svg, make_icons.py: app icons (PNG generated during build)

Build and deployment: .github/workflows/iphone-pages.yml. After GitHub Pages has been enabled, pushes to iphone/ automatically update the website.
