#!/bin/zsh
# Build GTime.app, ad-hoc sign it, install and (re)launch.
set -e
cd "$(dirname "$0")"

echo "==> Running tests"
mkdir -p build
swiftc Sources/GTimeCore.swift Tests/main.swift -o build/tests
./build/tests

echo "==> Compiling"
swiftc -O Sources/GTimeCore.swift Sources/main.swift -o build/GTime

echo "==> Packaging GTime.app"
APP=build/GTime.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp build/GTime "$APP/Contents/MacOS/GTime"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.sijie.gtime</string>
	<key>CFBundleName</key>
	<string>GTime</string>
	<key>CFBundleDisplayName</key>
	<string>GTime</string>
	<key>CFBundleExecutable</key>
	<string>GTime</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

echo "==> Installing"
DEST=/Applications
OTHER="$HOME/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  OTHER=/Applications
  mkdir -p "$DEST"
fi
# Stop a running copy and wait for it to actually exit before replacing it
pkill -x GTime 2>/dev/null || true
for _ in $(seq 1 30); do
  pgrep -x GTime >/dev/null || break
  sleep 0.1
done
# Drop any stale copy at the other candidate location so the LaunchAgent can't launch it
rm -rf "$OTHER/GTime.app" 2>/dev/null || true
rm -rf "$DEST/GTime.app"
cp -R "$APP" "$DEST/"

echo "==> Launching $DEST/GTime.app"
open "$DEST/GTime.app"
echo "Done."
