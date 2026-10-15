#!/bin/bash
set -euo pipefail
APP="$1"
DEST="$APP/Contents/Resources/tools"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$DEST/arm64" "$DEST/amd64"

fetch() {
  curl --fail --location --silent --show-error --retry 4 --retry-delay 3 \
    --connect-timeout 30 -o "$2" "$1"
}
verify() {
  local filename="$1" sums="$2" file="$3"
  local expected
  expected="$(awk -v target="$filename" '{name=$2; sub(/^\*/, "", name); if(name==target){print $1; exit}}' "$sums")"
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { echo "Missing checksum for $filename" >&2; exit 1; }
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || { echo "Checksum mismatch for $filename" >&2; exit 1; }
  echo "Verified: $filename"
}

YT="https://github.com/yt-dlp/yt-dlp/releases/latest/download"
fetch "$YT/SHA2-256SUMS" "$TEMP/yt-sums"
fetch "$YT/yt-dlp_macos" "$TEMP/yt-dlp_macos"
verify "yt-dlp_macos" "$TEMP/yt-sums" "$TEMP/yt-dlp_macos"
install -m 755 "$TEMP/yt-dlp_macos" "$DEST/yt-dlp_macos"

DENO="https://github.com/denoland/deno/releases/latest/download"
for pair in 'arm64:aarch64' 'amd64:x86_64'; do
  arch="$(echo "$pair" | cut -d: -f1)"
  target="$(echo "$pair" | cut -d: -f2)"
  asset="deno-$target-apple-darwin.zip"
  fetch "$DENO/$asset" "$TEMP/$asset"
  fetch "$DENO/$asset.sha256sum" "$TEMP/$asset.sha256sum"
  verify "$asset" "$TEMP/$asset.sha256sum" "$TEMP/$asset"
  mkdir -p "$TEMP/deno-$arch"
  unzip -q "$TEMP/$asset" -d "$TEMP/deno-$arch"
  test -f "$TEMP/deno-$arch/deno"
  install -m 755 "$TEMP/deno-$arch/deno" "$DEST/$arch/deno"
done

FF="https://github.com/binmgr/ffmpeg/releases/latest/download"
fetch "$FF/SHA256SUMS.txt" "$TEMP/ff-sums"
for arch in arm64 amd64; do
  asset="ffmpeg-darwin-$arch.tar.gz"
  fetch "$FF/$asset" "$TEMP/$asset"
  verify "$asset" "$TEMP/ff-sums" "$TEMP/$asset"
  mkdir -p "$TEMP/ff-$arch"
  tar -xzf "$TEMP/$asset" -C "$TEMP/ff-$arch"
  test -f "$TEMP/ff-$arch/ffmpeg"
  test -f "$TEMP/ff-$arch/ffprobe"
  install -m 755 "$TEMP/ff-$arch/ffmpeg" "$DEST/$arch/ffmpeg"
  install -m 755 "$TEMP/ff-$arch/ffprobe" "$DEST/$arch/ffprobe"
done
echo "All helper tools packaged and SHA-256 verified."
