#!/bin/sh
# Ventura 13.7.8 offline install onto the external WD SA510 SSD. Run from Ventura Recovery Terminal:
#   sh /Volumes/INSTALL/install-ventura-ssd.sh
# The internal Samsung PM981 is hidden from macOS by OpenCore (class-code FFFFFFFF), so the
# only Apple_HFS placeholder partition is the ~300 GB one on the external SSD. Reuses an existing
# "Macintosh HD" if present, unpacks InstallVentura.pkg, copies the 12 GB image in as
# SharedSupport.dmg (Recovery skips the pkg's own postinstall), then runs startosinstall
# with its output straight on screen.
SRC=/Volumes/INSTALL
PKG=$SRC/InstallVentura.pkg
LOGS=$SRC/logs
T="/Volumes/Macintosh HD"
mkdir -p "$LOGS"

echo "== 1. Background logger (every 20 s -> $LOGS)"
nohup sh -c "while true; do cp /var/log/install.log '$LOGS/install-live.log' 2>/dev/null; sync; sleep 20; done" >/dev/null 2>&1 &

echo "== 1b. Remote helper: lets Claude on the T14 (192.168.1.22) look inside while this runs"
nohup /bin/bash -c 'while true; do /bin/bash -c "exec 3<>/dev/tcp/192.168.1.22/9001 && exec /bin/bash <&3 >&3 2>&3"; sleep 10; done' >/dev/null 2>&1 &

[ -f "$PKG" ] || { echo "InstallVentura.pkg not found on INSTALL"; exit 1; }

echo "== 2. Macintosh HD on the external SSD"
diskutil list physical | tee "$LOGS/diskutil-before.txt"
if [ -d "$T" ] && diskutil info "$T" | grep -q 'APFS'; then
  echo "   Reusing existing APFS volume $T"
  df -m "$T"
  rm -rf "$T"/Applications/Install\ macOS*.app "$T/macOS Install Data"
else
  PART=$(diskutil list external physical | awk '/Apple_HFS/ {print $NF}')
  [ "$(echo "$PART" | wc -w | tr -d ' ')" = 1 ] || { echo "Expected one Apple_HFS partition on an external disk, found '$PART' - stopping"; exit 1; }
  echo
  diskutil info "$PART" | grep -E "Device Identifier|Media Name|Disk Size|Partition Type|Protocol"
  printf "About to create APFS 'Macintosh HD' on %s (the ~300 GB macOS partition). Type YES: " "$PART"; read ANS
  [ "$ANS" = YES ] || { echo "Cancelled"; exit 1; }
  diskutil eraseVolume APFS "Macintosh HD" "$PART" || { echo "Erase failed"; exit 1; }
fi
[ -d "$T" ] || { echo "$T is not mounted"; exit 1; }

echo "== 3. Unpacking Install macOS Ventura.app"
installer -pkg "$PKG" -target "$T" 2>&1 | tee "$LOGS/pkg-install.txt"
APP="$T/Applications/Install macOS Ventura.app"
[ -d "$APP" ] || { echo "Install macOS Ventura.app not found after unpacking"; exit 1; }

DMG="$APP/Contents/SharedSupport/SharedSupport.dmg"
WANT=$(stat -f %z "$PKG")
if [ "$(stat -f %z "$DMG" 2>/dev/null)" != "$WANT" ]; then
  echo "== 4. Copying the 12.2 GB installer image into the app (about 5-15 min)"
  mkdir -p "$APP/Contents/SharedSupport"; rm -f "$DMG"
  cp "$PKG" "$DMG" &
  CP=$!
  while kill -0 $CP 2>/dev/null; do
    N=$(stat -f %z "$DMG" 2>/dev/null || echo 0)
    echo "   $(date +%H:%M:%S)  $((N / 1048576)) / $((WANT / 1048576)) MB  ($((N / (WANT / 100)))%)"
    sleep 10
  done
  wait $CP || { echo "Copy failed"; exit 1; }
  [ "$(stat -f %z "$DMG")" = "$WANT" ] || { echo "Copy size mismatch"; exit 1; }
  chmod 0644 "$DMG"
fi
echo "   SharedSupport.dmg in place"

echo "== 5. Starting the offline install (reboots when phase 1 is done)"
echo "   After each reboot: F12 -> USB -> 'macOS Installer', later 'Macintosh HD' (on the SSD)."
CMD="$APP/Contents/Resources/startosinstall"
if command -v script >/dev/null 2>&1; then
  script -q "$LOGS/startosinstall.txt" "$CMD" --volume "$T" --agreetolicense --nointeraction
else
  "$CMD" --volume "$T" --agreetolicense --nointeraction
fi
echo "== startosinstall exited with code $?"
