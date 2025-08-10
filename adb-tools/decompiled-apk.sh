#!/bin/bash

# Usage:
# ./decompile-apk.sh <apk-file> [jadx|apktool]
# Default: uses apktool if not specified

APK="$1"
TOOL="${2:-apktool}"

if [ ! -f "$APK" ]; then
  echo "❌ APK file not found: $APK"
  echo "Usage: $0 <apk-file> [jadx|apktool]"
  exit 1
fi

BASENAME=$(basename "$APK" .apk)
OUTDIR="${BASENAME}-decompiled"

download_jadx() {
  echo "🟡 Downloading temporary jadx..."
  JADX_URL="https://github.com/skylot/jadx/releases/latest/download/jadx-bin.zip"
  TMPDIR=$(mktemp -d)
  wget -qO "$TMPDIR/jadx-bin.zip" "$JADX_URL"
  unzip -q "$TMPDIR/jadx-bin.zip" -d "$TMPDIR/jadx"
  echo "$TMPDIR/jadx/bin/jadx"
}

download_apktool() {
  echo "🟡 Downloading temporary apktool..."
  # Get latest version number
  VER=$(curl -s https://api.github.com/repos/iBotPeaches/Apktool/releases/latest | grep tag_name | cut -d'"' -f4)
  JAR="$HOME/.cache/apktool_${VER#v}.jar"
  WRAP="$HOME/.cache/apktool"
  wget -qO "$JAR" "https://github.com/iBotPeaches/Apktool/releases/download/$VER/apktool_${VER#v}.jar"
  wget -qO "$WRAP" "https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool"
  chmod +x "$WRAP"
  echo "$WRAP" "$JAR"
}

case "$TOOL" in
  jadx)
    if command -v jadx &>/dev/null; then
      JADXCMD="jadx"
    else
      JADXCMD=$(download_jadx)
    fi
    echo "🟢 Decompiling $APK with JADX..."
    mkdir -p "$OUTDIR"
    "$JADXCMD" -d "$OUTDIR" "$APK"
    echo "✅ Decompiled Java source in: $OUTDIR"
    ;;
  apktool)
    if command -v apktool &>/dev/null; then
      APKTOOLCMD="apktool"
      JAR=""
    else
      read APKTOOLCMD JAR < <(download_apktool)
    fi
    echo "🟢 Decompiling $APK with apktool..."
    if [ -n "$JAR" ]; then
      "$APKTOOLCMD" --java "$JAR" d "$APK" -o "$OUTDIR"
    else
      "$APKTOOLCMD" d "$APK" -o "$OUTDIR"
    fi
    echo "✅ Decompiled resources and smali code in: $OUTDIR"
    ;;
  *)
    echo "❌ Unknown tool: $TOOL (use 'jadx' or 'apktool')"
    exit 3
    ;;
esac