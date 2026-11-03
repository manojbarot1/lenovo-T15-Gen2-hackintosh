#!/bin/bash
# Run on the T15 macOS with sudo:
#   ssh -t manojb@192.168.1.17 'sudo bash ~/addk/mac-usbmap-port.sh HS07 255'
# Sets UsbConnector of one XHCI port in USBMap.kext in EFI\OC (MacPro7,1-XHCI) and
# EFI\OCXE (MacBookPro16,2-XHCI) on the external SSD's ESP. 255 = internal, which macOS
# Bluetooth requires (Intel AX201 BT is USB 8087:0026 on HS07, location 0x14700000).
# Backups: USBMap.kext/Contents/Info.plist.before-<port>
set -euo pipefail
PORT=${1:?port}; TYPE=${2:?UsbConnector}
PB=/usr/libexec/PlistBuddy
DEV=$(diskutil list external | awk '/OPENCORE/ {print $NF; exit}')
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
[ -n "$MP" ] || { echo "mount failed"; exit 1; }
trap 'sync; diskutil unmount "$DEV" >/dev/null 2>&1 || true' EXIT
for R in OC:MacPro7,1-XHCI OCXE:MacBookPro16,2-XHCI; do
  F="$MP/EFI/${R%%:*}/Kexts/USBMap.kext/Contents/Info.plist"; N=${R#*:}
  [ -f "$F.before-$PORT" ] || cp "$F" "$F.before-$PORT"
  K=":IOKitPersonalities:$N:IOProviderMergeProperties:ports:$PORT"
  $PB -c "Set $K:UsbConnector $TYPE" "$F"
  $PB -c "Set $K:comment Bluetooth (Intel AX201)" "$F" 2>/dev/null || $PB -c "Add $K:comment string Bluetooth (Intel AX201)" "$F"
  plutil -lint "$F"
  echo "${R%%:*} $PORT UsbConnector = $($PB -c "Print $K:UsbConnector" "$F")"
done
echo DONE
