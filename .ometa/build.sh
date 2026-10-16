#!/usr/bin/env bash
# The tweak is built from this fork's source (upstream's builddeb.yml: rootless + RootHide
# .debs), then injected into Spotify like upstream's build-and-release-yourself.yml:
# a plain IPA for TrollStore and a sideload IPA with zxPluginsInject.
source "$PIPELINE/lib/helpers.sh"

sudo xcode-select -s /Applications/Xcode_26.3.0.app
setup_theos "" master
install_cyan
ARCH=$(uname -m); [ "$ARCH" = x86_64 ] && S=macos-amd64 || S=macos-arm64
sudo curl -fsSL "https://github.com/asdfzxcvbn/ipapatch/releases/latest/download/ipapatch.$S" -o /usr/local/bin/ipapatch
sudo chmod +x /usr/local/bin/ipapatch

VERSION=$(awk '/^Version:/ {print $2}' control)

log "EeveeSwiftProtobuf.framework"
make build-eeveeswiftprotobuf

log "Rootless .deb"
make clean || true
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
ROOTLESS="$(ls -t packages/*.deb | head -1)"
cp "$ROOTLESS" "$OUT/"
ROOTLESS="$OUT/$(basename "$ROOTLESS")"

log "RootHide .deb (roothide/theos)"
(
  export THEOS="$RUNNER_TEMP/theos-roothide"
  git clone --quiet --recursive https://github.com/roothide/theos.git "$THEOS"
  rm -rf packages; make clean || true
  make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
  DEB="$(ls -t packages/*.deb | head -1)"
  cp "$DEB" "$OUT/$(basename "$DEB" .deb)-roothide.deb"
) || log "RootHide build failed; skipping it"
make clean || true

log "zxPluginsInject.dylib"
bash Tools/build-zxpi.sh

log "Injecting into Spotify $BASE_VERSION"
EXTRACT="$RUNNER_TEMP/deb-extract"; mkdir -p "$EXTRACT"
dpkg-deb -R "$ROOTLESS" "$EXTRACT"
INJECT=("$(find "$EXTRACT" -name 'EeveeSpotify.dylib' | head -1)")
F=$(find "$EXTRACT" -type d -name 'EeveeSwiftProtobuf.framework' | head -1); [ -n "$F" ] && INJECT+=("$F")
B=$(find "$EXTRACT" -type d -name 'EeveeSpotify.bundle' | head -1);        [ -n "$B" ] && INJECT+=("$B")
IPA="$OUT/EeveeSpotify_${BASE_VERSION}_v$VERSION.ipa"
cyan -i "$BASE_IPA" -o "$IPA" -f "${INJECT[@]}" -c 9 -m 15.0 -du

log "Open in Spotify Safari extension, no Watch app"
git clone --quiet --depth 1 https://github.com/BillyCurtis/OpenSpotifySafariExtension.git "$RUNNER_TEMP/ext"
W="$RUNNER_TEMP/ipa-work"; rm -rf "$W"; mkdir -p "$W"
unzip -q "$IPA" -d "$W"
APP="$W/Payload/Spotify.app"
mkdir -p "$APP/PlugIns"
rm -rf "$APP/com.apple.WatchPlaceholder" "$APP/Watch"
cp -R "$RUNNER_TEMP/ext/OpenSpotifySafariExtension.appex" "$APP/PlugIns/"
rm -f "$IPA"; (cd "$W" && zip -qry "$IPA" Payload)

log "Alternate app icons"
bash Tools/alt-icons.sh "$IPA"

log "Sideload IPA (zxPluginsInject)"
cp "$IPA" "${IPA%.ipa}_sideload.ipa"
ipapatch --input "${IPA%.ipa}_sideload.ipa" --inplace --noconfirm --dylib packages/zxPluginsInject.dylib
