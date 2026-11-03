#!/bin/bash
# Run on the T15 macOS with sudo, after copying AppleALC.kext to ~/alc/:
#   scp -r kexts/AppleALC/x/AppleALC.kext manojb@192.168.1.17:alc/
#   ssh -t manojb@192.168.1.17 'sudo bash ~/alc/mac-applealc.sh 11'
# Needs System Settings > Sharing > Remote Login (i) > "Allow full disk access for remote
# users" (otherwise TCC blocks disk access over SSH). macOS only: PlistBuddy, no Python.
# Adds AppleALC after Lilu in EFI\OC and EFI\OCXE and sets layout-id on HDAS (0:31:3).
# Backups: config.plist.before-applealc
set -euo pipefail
LAYOUT=${1:?layout-id}
SRC="$(cd "$(dirname "$0")" && pwd)/AppleALC.kext"
PB=/usr/libexec/PlistBuddy
DEV=$(diskutil list external | awk '/OPENCORE/ {print $NF; exit}')
[ -n "$DEV" ] || { echo "OPENCORE partition not found"; exit 1; }
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
[ -n "$MP" ] || { echo "mount failed"; exit 1; }
trap 'sync; diskutil unmount "$DEV" >/dev/null 2>&1 || true' EXIT
echo "OpenCore ESP: $DEV at $MP"
HEX=$(printf '%02x000000' "$LAYOUT")
for R in OC OCXE; do
  E="$MP/EFI/$R"; C="$E/config.plist"
  [ -f "$C.before-applealc" ] || cp "$C" "$C.before-applealc"
  rm -rf "$E/Kexts/AppleALC.kext"; ditto "$SRC" "$E/Kexts/AppleALC.kext"
  N=0; LILU=""; ALC=""
  while P=$($PB -c "Print :Kernel:Add:$N:BundlePath" "$C" 2>/dev/null); do
    [ "$P" = Lilu.kext ] && LILU=$N
    [ "$P" = AppleALC.kext ] && ALC=$N
    N=$((N+1))
  done
  if [ -z "$ALC" ]; then
    ALC=$((LILU+1))
    $PB -c "Add :Kernel:Add:$ALC dict" \
        -c "Add :Kernel:Add:$ALC:Arch string Any" \
        -c "Add :Kernel:Add:$ALC:BundlePath string AppleALC.kext" \
        -c "Add :Kernel:Add:$ALC:Comment string Audio (Realtek on Tiger Lake HDA)" \
        -c "Add :Kernel:Add:$ALC:Enabled bool true" \
        -c "Add :Kernel:Add:$ALC:ExecutablePath string Contents/MacOS/AppleALC" \
        -c "Add :Kernel:Add:$ALC:MaxKernel string" \
        -c "Add :Kernel:Add:$ALC:MinKernel string" \
        -c "Add :Kernel:Add:$ALC:PlistPath string Contents/Info.plist" "$C"
  fi
  K="PciRoot(0x0)/Pci(0x1f,0x3)"
  $PB -c "Print ':DeviceProperties:Add:$K'" "$C" >/dev/null 2>&1 || $PB -c "Add ':DeviceProperties:Add:$K' dict" "$C"
  $PB -c "Delete ':DeviceProperties:Add:$K:layout-id'" "$C" >/dev/null 2>&1 || true
  printf "$(echo $HEX | sed 's/../\\x&/g')" > /tmp/layout-id.bin
  $PB -c "Import ':DeviceProperties:Add:$K:layout-id' /tmp/layout-id.bin" "$C"
  plutil -lint "$C"
  echo "$R: Lilu at $LILU, AppleALC at $ALC, layout-id $LAYOUT = $($PB -c "Print ':DeviceProperties:Add:$K:layout-id'" "$C" | xxd -p)"
done
echo DONE
