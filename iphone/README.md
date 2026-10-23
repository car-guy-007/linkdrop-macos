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


## Free Mac bridge for video sites

The iPhone web app can use your own Mac as the download engine. There is no paid download host. The Mac must stay awake and online while processing and sending a file.

### One-time setup

1. Install **Tailscale** on your Mac and iPhone and sign in to the same personal account. Tailscale's personal plan is free. Use its official download page: https://tailscale.com/download.
2. Install LinkDrop.app in your Mac's **Applications** folder and open it once.
3. On the Mac, open Terminal and run:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/car-guy-007/linkdrop-macos/main/iphone/mac_bridge.py -o "$HOME/Downloads/linkdrop-mac-bridge.py"
   python3 "$HOME/Downloads/linkdrop-mac-bridge.py"
   ```

   Keep that Terminal window open. It prints a long **pairing token**. Copy it; do not share it.
4. In a second Terminal window, run:

   ```sh
   tailscale serve --bg 8765
   tailscale serve status
   ```

   The status output should show the HTTPS address for your Mac. If Tailscale asks you to enable HTTPS, follow its prompt.
5. Open the LinkDrop iPhone web app in Safari. Enter that HTTPS address and the pairing token in **Connect your Mac**, then tap **Connect to Mac**.
6. Paste a supported video page, choose quality, tap **Get video details**, then **Download on Mac**. When complete, tap **Save to iPhone**.

### Important notes

- The helper binds only to your Mac's loopback interface. Use Tailscale Serve; **do not port-forward port 8765 or expose it directly to the public internet**.
- Keep the pairing token private. The app stores it in this iPhone browser's local storage. If you believe it was exposed, stop the helper and remove `~/Library/Application Support/LinkDrop/remote-token` before restarting to generate a new token.
- Downloads are saved to the Mac's `~/Downloads` folder first, then transferred directly to the iPhone through the encrypted Tailscale connection.
- The Mac helper requires Python 3 and the LinkDrop app's bundled yt-dlp tool. If `python3` is missing, install Python from its official site.
- Site support can change. Login-required/private videos may fail; DRM and access controls are not bypassed. Only download content you are authorized to save.
- This is an early beta bridge. Keep the Mac and iPhone software updated, and stop the helper with Control-C when not using it.
