(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const urlInput = $("url"), recentList = $("recent-list");
  const savedKey = "linkdrop-iphone-recents-v2";
  const configKey = "linkdrop-mac-bridge-v1";
  const formats = /\.(mp4|m4v|mov|webm|mp3|m4a|aac|wav|ogg|oga|flac)$/i;
  const videoPages = ["youtube.com","youtu.be","instagram.com","tiktok.com","facebook.com","fb.watch","vimeo.com","dailymotion.com","twitch.tv","twitter.com","x.com","bilibili.com","reddit.com","streamable.com"];
  let jobRunning = false, lastVideoUrl = "";

  function config() {
    try { return JSON.parse(localStorage.getItem(configKey) || "{}"); } catch (_) { return {}; }
  }
  function saveConfig() {
    const endpoint = $("bridge-url").value.trim().replace(/\/+$/, "");
    const token = $("bridge-token").value.trim();
    let parsed;
    try { parsed = new URL(endpoint); } catch (_) { return bridgeMessage("Enter the HTTPS address shown by Tailscale Serve."); }
    if (parsed.protocol !== "https:" && !(parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1")) {
      return bridgeMessage("Use the HTTPS Tailscale address. Plain HTTP is not secure for remote pairing.");
    }
    if (!token || token.length < 30) return bridgeMessage("Paste the full pairing token from the Mac bridge.");
    try { localStorage.setItem(configKey, JSON.stringify({endpoint, token})); } catch (_) {}
    connectBridge();
  }
  function readHistory() {
    try { const v = JSON.parse(localStorage.getItem(savedKey) || "[]"); return Array.isArray(v) ? v.filter(x => typeof x === "string").slice(0, 6) : []; } catch (_) { return []; }
  }
  function storeHistory(link) {
    try { localStorage.setItem(savedKey, JSON.stringify([link, ...readHistory().filter(x => x !== link)].slice(0, 6))); } catch (_) {}
    renderHistory();
  }
  function showMessage(message, good = false) {
    const box = $("message"); box.textContent = message; box.classList.toggle("success", good); box.hidden = false;
  }
  function clearMessage() { $("message").hidden = true; $("message").textContent = ""; }
  function bridgeMessage(message, good = false) {
    const box = $("bridge-message"); box.textContent = message; box.classList.toggle("success", good); box.hidden = false;
  }
  function parseLink(text) {
    let raw = (text || "").trim();
    if (/^www\./i.test(raw)) raw = "https://" + raw;
    let parsed;
    try { parsed = new URL(raw); } catch (_) { return null; }
    if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname || parsed.username || parsed.password) return null;
    return parsed;
  }
  function isVideoPage(host) { return videoPages.some(name => host === name || host.endsWith("." + name)); }
  async function api(path, options = {}) {
    const cfg = config();
    if (!cfg.endpoint || !cfg.token) throw new Error("Connect your Mac first.");
    const response = await fetch(cfg.endpoint + path, {
      ...options,
      headers: { "Authorization": "Bearer " + cfg.token, ...(options.body ? {"Content-Type":"application/json"} : {}), ...(options.headers || {}) },
      cache: "no-store"
    });
    let body = {};
    try { body = await response.json(); } catch (_) {}
    if (!response.ok) throw new Error(body.error || "Mac bridge request failed (" + response.status + ").");
    return body;
  }
  async function connectBridge() {
    const cfg = config();
    if (!cfg.endpoint || !cfg.token) return bridgeMessage("Enter your Mac HTTPS address and pairing token.");
    $("connect").disabled = true; $("bridge-status").textContent = "Connecting…";
    try {
      await api("/api/jobs");
      $("bridge-status").textContent = "Connected";
      bridgeMessage("Connected securely to your Mac. You can now check video links.", true);
    } catch (err) {
      $("bridge-status").textContent = "Not connected";
      bridgeMessage(err.message + " Make sure the Mac bridge and Tailscale Serve are running.");
    } finally { $("connect").disabled = false; }
  }
  function makeAction(label, url, download) {
    const a = document.createElement("a"); a.textContent = label; a.className = "action" + (download ? "" : " secondary");
    a.href = url; a.target = "_blank"; a.rel = "noopener noreferrer";
    if (download) a.setAttribute("download", decodeURIComponent(new URL(url).pathname.split("/").pop() || "media"));
    return a;
  }
  function setResult(title, detail, help) {
    $("result-title").textContent = title; $("result-detail").textContent = detail; $("result-help").textContent = help;
    $("result-actions").replaceChildren(); $("result").hidden = false;
  }
  async function resultFor(parsed) {
    const actions = $("result-actions"), host = parsed.hostname.replace(/^www\./, "");
    if (formats.test(parsed.pathname)) {
      setResult("Direct media link found", "This appears to be a media file hosted on " + host + ".", "Safari decides whether to download or play the file. If it plays, use Share → Save to Files when available.");
      actions.append(makeAction("↓ Download file", parsed.href, true), makeAction("Open in Safari ↗", parsed.href, false));
      return;
    }
    if (!isVideoPage(host)) {
      setResult("Checking with your Mac", "This may be a video page or a direct media link without a file extension.", "Your Mac will try to read the link using its download engine.");
    } else {
      setResult("Getting video details…", "Asking your Mac to inspect this link.", "Your Mac does the processing locally.");
    }
    const cfg = config();
    if (!cfg.endpoint || !cfg.token) {
      setResult("Connect your Mac first", "This is a webpage, not a direct media file.", "Enter the HTTPS address and pairing token above, then tap Connect to Mac.");
      actions.append(makeAction("Open original ↗", parsed.href, false));
      return;
    }
    lastVideoUrl = parsed.href;
    try {
      const meta = await api("/api/info", {method:"POST", body:JSON.stringify({url:parsed.href})});
      if (lastVideoUrl !== parsed.href) return;
      const duration = Number.isFinite(Number(meta.duration)) && meta.duration > 0
        ? " · " + Math.floor(meta.duration / 60) + ":" + String(Math.floor(meta.duration % 60)).padStart(2, "0") : "";
      setResult("Video ready", meta.title + duration + (meta.uploader ? " · " + meta.uploader : ""), "Choose a quality above, then start the download. The Mac saves a copy in its Downloads folder.");
      const start = document.createElement("button"); start.type = "button"; start.className = "action"; start.textContent = "↓ Download on Mac";
      start.addEventListener("click", () => startDownload(parsed.href)); actions.append(start, makeAction("Open original ↗", parsed.href, false));
    } catch (err) {
      setResult("Could not read this link", err.message, "Check that the Mac is awake, the bridge is running, and the site supports downloading. Private, DRM-protected, or login-required videos may not work.");
      actions.append(makeAction("Open original ↗", parsed.href, false));
    }
  }
  async function startDownload(url) {
    if (jobRunning) return;
    jobRunning = true;
    const actions = $("result-actions"); actions.replaceChildren();
    setResult("Starting download…", "Your Mac is preparing the file.", "Keep the Mac awake and connected to the internet.");
    const progress = document.createElement("progress"); progress.max = 100; progress.value = 0; progress.style.width = "100%"; progress.style.marginTop = "12px";
    actions.append(progress);
    try {
      const created = await api("/api/download", {method:"POST",body:JSON.stringify({url,quality:$("quality").value,playlist:false})});
      let job;
      for (let i = 0; i < 1800; i++) {
        await new Promise(resolve => setTimeout(resolve, 2000));
        job = await api("/api/jobs/" + created.id);
        progress.value = Number(job.progress || 0);
        $("result-title").textContent = job.status || "Working…";
        $("result-detail").textContent = job.state === "downloading" ? "Download progress: " + Math.round(job.progress || 0) + "%" : "The Mac is processing your video.";
        if (["done","error"].includes(job.state)) break;
      }
      if (!job || !["done","error"].includes(job.state)) throw new Error("This download is taking longer than expected. Check the Mac's Downloads folder.");
      if (job.state === "error") throw new Error(job.status || "Download failed.");
      setResult("Download complete", "The file is saved in your Mac's Downloads folder.", "Tap Save to iPhone to transfer it. Keep this page open while the file is being prepared.");
      const ticket = await api("/api/jobs/" + created.id + "/ticket");
      const save = document.createElement("a"); save.className = "action"; save.textContent = "↓ Save to iPhone"; save.href = config().endpoint + ticket.url; save.rel = "noopener"; actions.append(save);
      actions.append(makeAction("Open original ↗", url, false));
    } catch (err) {
      setResult("Download stopped", err.message, "If needed, try a different quality or update the yt-dlp engine in the Mac app.");
      const retry = document.createElement("button"); retry.type = "button"; retry.className = "action"; retry.textContent = "Try again"; retry.addEventListener("click", () => startDownload(url)); actions.append(retry);
    } finally { jobRunning = false; }
  }
  async function checkLink() {
    const parsed = parseLink(urlInput.value);
    if (!parsed) { $("result").hidden = true; showMessage("Enter a valid http:// or https:// link, without a username or password."); urlInput.focus(); return; }
    clearMessage(); storeHistory(parsed.href); await resultFor(parsed);
    if (typeof $("result").scrollIntoView === "function") $("result").scrollIntoView({behavior:"smooth",block:"nearest"});
  }
  function renderHistory() {
    const entries = readHistory(); $("recents").hidden = entries.length === 0; recentList.replaceChildren();
    for (const link of entries) {
      const button = document.createElement("button"); button.type = "button"; button.className = "recent-item";
      const symbol = document.createElement("span"); symbol.textContent = "↗"; symbol.style.flexShrink = "0"; symbol.style.color = "#7bdcc7";
      const label = document.createElement("span"); label.textContent = link; button.append(symbol,label);
      button.addEventListener("click", () => { urlInput.value = link; checkLink(); }); recentList.append(button);
    }
  }
  $("check").addEventListener("click", checkLink);
  $("connect").addEventListener("click", saveConfig);
  urlInput.addEventListener("keydown", event => { if (event.key === "Enter") { event.preventDefault(); checkLink(); } });
  urlInput.addEventListener("input", clearMessage);
  $("paste").addEventListener("click", async () => {
    try { const text = await navigator.clipboard.readText(); if (!text) return showMessage("Your clipboard is empty."); urlInput.value = text.trim(); clearMessage(); checkLink(); }
    catch (_) { urlInput.focus(); showMessage("Safari couldn't read the clipboard. Touch and hold the field, then tap Paste."); }
  });
  $("clear").addEventListener("click", () => { try { localStorage.removeItem(savedKey); } catch (_) {} renderHistory(); });
  const cfg = config(); if (cfg.endpoint) $("bridge-url").value = cfg.endpoint; if (cfg.token) $("bridge-token").value = cfg.token;
  const initialLink = new URLSearchParams(location.search).get("url"); if (initialLink) { urlInput.value = initialLink; checkLink(); }
  renderHistory();
  if ("serviceWorker" in navigator && location.protocol === "https:") navigator.serviceWorker.register("./sw.js").catch(() => {});
})();