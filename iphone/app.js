(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const urlInput = $("url");
  const recentList = $("recent-list");
  const savedKey = "linkdrop-iphone-recents-v1";
  const formats = /\.(mp4|m4v|mov|webm|mp3|m4a|aac|wav|ogg|oga|flac)$/i;
  const videoPages = [
    "youtube.com", "youtu.be", "instagram.com", "tiktok.com",
    "facebook.com", "fb.watch", "vimeo.com", "dailymotion.com",
    "twitch.tv", "twitter.com", "x.com", "bilibili.com", "reddit.com",
    "streamable.com"
  ];

  function readHistory() {
    try {
      const parsed = JSON.parse(localStorage.getItem(savedKey) || "[]");
      return Array.isArray(parsed) ? parsed.filter((x) => typeof x === "string").slice(0, 8) : [];
    } catch (_) {
      return [];
    }
  }
  function storeHistory(link) {
    try {
      const prev = readHistory();
      localStorage.setItem(savedKey, JSON.stringify([link, ...prev.filter((x) => x !== link)].slice(0, 6)));
    } catch (_) { /* Private browsing may block local storage. */ }
    renderHistory();
  }
  function showMessage(message, good = false) {
    const box = $("message");
    box.textContent = message;
    box.classList.toggle("success", good);
    box.hidden = false;
  }
  function clearMessage() {
    $("message").hidden = true;
    $("message").textContent = "";
  }
  function parseLink(text) {
    let raw = (text || "").trim();
    if (/^www\./i.test(raw)) raw = "https://" + raw;
    let parsed;
    try { parsed = new URL(raw); } catch (_) { return null; }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
    if (!parsed.hostname) return null;
    // Prevent links that might reveal local address space or contain embedded credentials.
    if (parsed.username || parsed.password) return null;
    return parsed;
  }
  function isVideoPage(host) {
    return videoPages.some((name) => host === name || host.endsWith("." + name));
  }
  function makeAction(label, url, download) {
    const a = document.createElement("a");
    a.textContent = label;
    a.className = "action" + (download ? "" : " secondary");
    a.href = url;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    // This is a *request* to the browser. Cross-origin servers may force playback.
    if (download) {
      a.setAttribute("download", decodeURIComponent(new URL(url).pathname.split("/").pop() || "video"));
    }
    return a;
  }
  function resultFor(parsed) {
    const box = $("result"), title = $("result-title");
    const detail = $("result-detail"), actions = $("result-actions");
    const help = $("result-help");
    actions.replaceChildren();
    const host = parsed.hostname.replace(/^www\./, "");
    const pathname = parsed.pathname;
    const isDirect = formats.test(pathname);
    title.textContent = isDirect ? "Direct media link found" : isVideoPage(host)
      ? "This site needs a download engine" : "Link ready to open";

    if (isDirect) {
      detail.textContent = "This looks like a direct video or audio file hosted on " + host + ".";
      actions.append(makeAction("↓ Download file", parsed.href, true), makeAction("Open in Safari ↗", parsed.href, false));
      help.textContent = "The website controls whether Safari downloads the file or opens a player. If it plays, use Safari's Share → Save to Files when available.";
    } else if (isVideoPage(host)) {
      detail.textContent = "This is a " + host + " video page, not a direct media file. An iPhone-only web app cannot extract and download its video without a separate supported server.";
      actions.append(makeAction("Open original ↗", parsed.href, false));
      help.textContent = "The Mac LinkDrop app has a local download engine. Adding similar support on iPhone requires a hosted download service. DRM and inaccessible content remain unsupported.";
    } else {
      detail.textContent = "This may be a webpage or a direct file link without a filename extension. Safari can open it, but LinkDrop cannot confirm the file type.";
      actions.append(makeAction("Try download ↓", parsed.href, true), makeAction("Open link ↗", parsed.href, false));
      help.textContent = "Only links that actually return downloadable files will work. Video pages generally require a download engine.";
    }
    box.hidden = false;
    if (typeof box.scrollIntoView === "function") {
      box.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
  }
  function checkLink() {
    const parsed = parseLink(urlInput.value);
    if (!parsed) {
      $("result").hidden = true;
      showMessage("Enter a valid http:// or https:// link, with no embedded username or password.");
      urlInput.focus();
      return;
    }
    clearMessage();
    storeHistory(parsed.href);
    resultFor(parsed);
  }
  function renderHistory() {
    const entries = readHistory();
    const wrapper = $("recents");
    wrapper.hidden = entries.length === 0;
    recentList.replaceChildren();
    for (const link of entries) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "recent-item";
      const symbol = document.createElement("span");
      symbol.textContent = "↗";
      symbol.style.flexShrink = "0";
      symbol.style.color = "#7bdcc7";
      const label = document.createElement("span");
      label.textContent = link;
      button.append(symbol, label);
      button.addEventListener("click", () => { urlInput.value = link; checkLink(); });
      recentList.append(button);
    }
  }

  $("check").addEventListener("click", checkLink);
  urlInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") { event.preventDefault(); checkLink(); }
  });
  urlInput.addEventListener("input", clearMessage);
  $("paste").addEventListener("click", async () => {
    try {
      const text = await navigator.clipboard.readText();
      if (!text) return showMessage("Your clipboard is empty.");
      urlInput.value = text.trim();
      clearMessage();
      checkLink();
    } catch (_) {
      urlInput.focus();
      showMessage("Safari couldn't read the clipboard. Touch and hold the field, then tap Paste.");
    }
  });
  $("clear").addEventListener("click", () => {
    try { localStorage.removeItem(savedKey); } catch (_) {}
    renderHistory();
  });

  const initialLink = new URLSearchParams(location.search).get("url");
  if (initialLink) {
    urlInput.value = initialLink;
    checkLink();
  }
  renderHistory();
  if ("serviceWorker" in navigator && (location.protocol === "https:" || location.hostname === "localhost")) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
})();