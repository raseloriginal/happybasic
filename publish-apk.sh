#!/usr/bin/env bash
# Copies the freshly built APK into releases/app/ (name from pubspec version). Then: git add releases && commit && push to draft.
set -euo pipefail
cd "$(dirname "$0")"
v=$(grep -E '^version:' mobile-app/pubspec.yaml | awk '{print $2}')
src=mobile-app/build/app/outputs/flutter-apk/app-release.apk
[ -f "$src" ] || { echo "build first: flutter build apk --release --target-platform android-arm,android-arm64"; exit 1; }
dst="releases/app/happybangladesh-${v%+*}-${v#*+}.apk"
cp "$src" "$dst"
[ -n "${1:-}" ] && printf '%s\n' "$1" > "$dst.txt"
echo "ready: $dst"
