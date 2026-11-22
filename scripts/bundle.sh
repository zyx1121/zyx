#!/bin/sh
# Builds .build/dist/zyx.app, universal (Apple silicon and Intel), unsigned.
set -eu
cd "$(dirname "$0")/.."
version=$(cat version.txt)
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)
args="-c release --arch arm64 --arch x86_64 --product Zyx"
swift build $args
bin=$(swift build $args --show-bin-path)

# Outside iCloud: its extended attributes break code signing.
app=.build/dist/zyx.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Zyx" "$app/Contents/MacOS/Zyx"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > "$app/Contents/Info.plist"
# The Icon Composer icon: Assets.car for macOS 26 and later, and an
# AppIcon.icns that actool renders from it for earlier versions.
xcrun actool Resources/AppIcon.icon --compile "$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon --include-all-app-icons \
  --output-partial-info-plist "$(mktemp -d)/icon.plist" >/dev/null
plutil -lint "$app/Contents/Info.plist" >/dev/null
echo "$app: $version ($build)"
