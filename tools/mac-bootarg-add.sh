#!/bin/bash
# Run on the T15 macOS with sudo:  ssh -t manojb@192.168.1.17 'sudo bash ~/addk/mac-bootarg-add.sh -btlfxa2dpcheck'
# Appends one boot-arg to NVRAM > Add boot-args in EFI\OC and EFI\OCXE (skips it if present).
# Backups: config.plist.before-<arg>
set -euo pipefail
ARG=${1:?boot-arg}
PB=/usr/libexec/PlistBuddy
G=7C436110-AB2A-4BBB-A880-FE41995C9F82
DEV=$(diskutil list external | awk '/OPENCORE/ {print $NF; exit}')
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
[ -n "$MP" ] || { echo "mount failed"; exit 1; }
trap 'sync; diskutil unmount "$DEV" >/dev/null 2>&1 || true' EXIT
for R in OC OCXE; do
  C="$MP/EFI/$R/config.plist"
  [ -f "$C.before$ARG" ] || cp "$C" "$C.before$ARG"
  A=$($PB -c "Print :NVRAM:Add:$G:boot-args" "$C")
  case " $A " in *" $ARG "*) ;; *) $PB -c "Set :NVRAM:Add:$G:boot-args $A $ARG" "$C";; esac
  plutil -lint "$C"
  echo "$R boot-args: $($PB -c "Print :NVRAM:Add:$G:boot-args" "$C")"
done
echo DONE
