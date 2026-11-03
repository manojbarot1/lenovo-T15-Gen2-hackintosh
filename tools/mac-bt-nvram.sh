#!/bin/bash
# Run on the T15 macOS with sudo:  ssh -t manojb@192.168.1.17 'sudo bash ~/addk/mac-bt-nvram.sh'
# Intel Bluetooth on macOS 12.4+ (BrcmPatchRAM README): OpenCore must set
#   bluetoothExternalDongleFailed = 00, bluetoothInternalControllerInfo = 14 x 00
# under 7C436110-..., and boot-arg -btlfxallowanyaddr skips the new address check.
# Both variables also go into NVRAM > Delete so OpenCore rewrites them on every boot.
# Applies to EFI\OC and EFI\OCXE. Backups: config.plist.before-bt-nvram
set -euo pipefail
PB=/usr/libexec/PlistBuddy
G=7C436110-AB2A-4BBB-A880-FE41995C9F82
DEV=$(diskutil list external | awk '/OPENCORE/ {print $NF; exit}')
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
[ -n "$MP" ] || { echo "mount failed"; exit 1; }
trap 'sync; diskutil unmount "$DEV" >/dev/null 2>&1 || true' EXIT
printf '\x00' > /tmp/bt1.bin
printf '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > /tmp/bt14.bin
for R in OC OCXE; do
  C="$MP/EFI/$R/config.plist"
  [ -f "$C.before-bt-nvram" ] || cp "$C" "$C.before-bt-nvram"
  for V in bluetoothExternalDongleFailed:/tmp/bt1.bin bluetoothInternalControllerInfo:/tmp/bt14.bin; do
    K=${V%%:*}
    $PB -c "Delete :NVRAM:Add:$G:$K" "$C" >/dev/null 2>&1 || true
    $PB -c "Import :NVRAM:Add:$G:$K ${V#*:}" "$C"
    $PB -c "Print :NVRAM:Delete:$G" "$C" | grep -qx "    $K" || $PB -c "Add :NVRAM:Delete:$G: string $K" "$C"
  done
  A=$($PB -c "Print :NVRAM:Add:$G:boot-args" "$C")
  case " $A " in *" -btlfxallowanyaddr "*) ;; *) $PB -c "Set :NVRAM:Add:$G:boot-args $A -btlfxallowanyaddr" "$C";; esac
  plutil -lint "$C"
  echo "$R boot-args: $($PB -c "Print :NVRAM:Add:$G:boot-args" "$C")"
  echo "$R Delete: $($PB -c "Print :NVRAM:Delete:$G" "$C" | tr -s ' \n' ' ')"
done
echo DONE
