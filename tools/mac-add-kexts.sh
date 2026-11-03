#!/bin/bash
# Run on the T15 macOS with sudo, with the .kext folders copied next to this script:
#   scp -r <kexts> tools/mac-add-kexts.sh manojb@192.168.1.17:addk/
#   ssh -t manojb@192.168.1.17 'sudo bash ~/addk/mac-add-kexts.sh A.kext B.kext ...'
# Copies the kexts into EFI\OC and EFI\OCXE on the external SSD's ESP and adds them to
# Kernel > Add right after Lilu, in the order given (existing entries are replaced in place).
# Needs Remote Login's "Allow full disk access for remote users". PlistBuddy only, no Python.
# Backups: config.plist.before-<first kext name>
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: $0 A.kext [B.kext ...]"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
PB=/usr/libexec/PlistBuddy
DEV=$(diskutil list external | awk '/OPENCORE/ {print $NF; exit}')
[ -n "$DEV" ] || { echo "OPENCORE partition not found"; exit 1; }
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
[ -n "$MP" ] || { echo "mount failed"; exit 1; }
trap 'sync; diskutil unmount "$DEV" >/dev/null 2>&1 || true' EXIT
echo "OpenCore ESP: $DEV at $MP"
TAG=$(basename "$1" .kext)
index_of() { local n=0 p; while p=$($PB -c "Print :Kernel:Add:$n:BundlePath" "$2" 2>/dev/null); do
  [ "$p" = "$1" ] && { echo $n; return; }; n=$((n+1)); done; }
for R in OC OCXE; do
  E="$MP/EFI/$R"; C="$E/config.plist"
  [ -f "$C.before-$TAG" ] || cp "$C" "$C.before-$TAG"
  AT=$(index_of Lilu.kext "$C")
  for K in "$@"; do
    [ -d "$HERE/$K" ] || { echo "missing $HERE/$K"; exit 1; }
    rm -rf "$E/Kexts/$K"; ditto "$HERE/$K" "$E/Kexts/$K"
    OLD=$(index_of "$K" "$C"); [ -z "$OLD" ] || $PB -c "Delete :Kernel:Add:$OLD" "$C"
    AT=$(index_of Lilu.kext "$C"); for P in "$@"; do [ "$P" = "$K" ] && break
      I=$(index_of "$P" "$C"); [ -n "$I" ] && [ "$I" -gt "$AT" ] && AT=$I; done
    AT=$((AT+1)); X=$(basename "$K" .kext)
    $PB -c "Add :Kernel:Add:$AT dict" \
        -c "Add :Kernel:Add:$AT:Arch string Any" \
        -c "Add :Kernel:Add:$AT:BundlePath string $K" \
        -c "Add :Kernel:Add:$AT:Comment string $X" \
        -c "Add :Kernel:Add:$AT:Enabled bool true" \
        -c "Add :Kernel:Add:$AT:ExecutablePath string Contents/MacOS/$X" \
        -c "Add :Kernel:Add:$AT:MaxKernel string" \
        -c "Add :Kernel:Add:$AT:MinKernel string" \
        -c "Add :Kernel:Add:$AT:PlistPath string Contents/Info.plist" "$C"
  done
  plutil -lint "$C"
  echo -n "$R:"; n=0; while P=$($PB -c "Print :Kernel:Add:$n:BundlePath" "$C" 2>/dev/null); do
    [ $n -lt 8 ] && echo -n " $n=$P"; n=$((n+1)); done; echo
done
echo DONE
