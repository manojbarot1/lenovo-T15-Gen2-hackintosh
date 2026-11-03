#!/bin/bash
# Run on the T15 macOS with sudo (copied to ~/airport/ together with AirportItlwm.kext):
#   sudo bash ~/airport/mac-airportitlwm.sh
# Switches the SSD's OpenCore from itlwm (shows as Ethernet) to AirportItlwm (native Wi-Fi
# menu). itlwm stays on disk, disabled. Backup: EFI/OC/config.plist.before-airportitlwm.
# Undo: copy the backup over config.plist (from macOS, or from Debian by mounting the ESP).
set -eu
SRC="$(dirname "$0")/AirportItlwm.kext"
PB=/usr/libexec/PlistBuddy
DEV=$(diskutil list external | awk '/OPENCORE/ {print $NF; exit}')
[ -n "$DEV" ] || { echo "OPENCORE partition not found"; exit 1; }
if ! diskutil mount "$DEV" >/dev/null 2>&1; then
  echo "--- mount refused; checking the FAT file system (read-only):"
  fsck_msdos -n "/dev/r$DEV" || true
  echo "--- repairing (usually just the dirty flag):"
  fsck_msdos -y "/dev/r$DEV" || true
  diskutil mount "$DEV" >/dev/null 2>&1 || { mkdir -p /Volumes/OCESP; mount -t msdos "/dev/$DEV" /Volumes/OCESP; }
fi
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
[ -n "$MP" ] || MP=/Volumes/OCESP
E="$MP/EFI/OC"; C="$E/config.plist"
echo "OpenCore ESP: $DEV at $MP"
[ -f "$C" ] || { echo "no $C"; exit 1; }
[ -f "$C.before-airportitlwm" ] || cp "$C" "$C.before-airportitlwm"

rm -rf "$E/Kexts/AirportItlwm.kext"; ditto "$SRC" "$E/Kexts/AirportItlwm.kext"

N=0; ITL=""; AIR=""
while P=$($PB -c "Print :Kernel:Add:$N:BundlePath" "$C" 2>/dev/null); do
  [ "$P" = itlwm.kext ] && ITL=$N
  [ "$P" = AirportItlwm.kext ] && AIR=$N
  N=$((N+1))
done
[ -n "$ITL" ] && $PB -c "Set :Kernel:Add:$ITL:Enabled false" "$C" && echo "itlwm.kext disabled (entry $ITL)"
if [ -z "$AIR" ]; then
  AIR=$N
  $PB -c "Add :Kernel:Add:$AIR dict" \
      -c "Add :Kernel:Add:$AIR:Arch string Any" \
      -c "Add :Kernel:Add:$AIR:BundlePath string AirportItlwm.kext" \
      -c "Add :Kernel:Add:$AIR:Comment string Intel Wi-Fi (native, Ventura build)" \
      -c "Add :Kernel:Add:$AIR:Enabled bool true" \
      -c "Add :Kernel:Add:$AIR:ExecutablePath string Contents/MacOS/AirportItlwm" \
      -c "Add :Kernel:Add:$AIR:MaxKernel string 22.99.99" \
      -c "Add :Kernel:Add:$AIR:MinKernel string 22.0.0" \
      -c "Add :Kernel:Add:$AIR:PlistPath string Contents/Info.plist" "$C"
fi
$PB -c "Set :Kernel:Add:$AIR:Enabled true" "$C"
plutil -lint "$C"
echo "--- Kernel > Add now:"
N=0; while P=$($PB -c "Print :Kernel:Add:$N:BundlePath" "$C" 2>/dev/null); do
  echo "  $N $P enabled=$($PB -c "Print :Kernel:Add:$N:Enabled" "$C")"; N=$((N+1)); done
ls "$E/Kexts"
sync; diskutil unmount "$DEV" >/dev/null && echo "ESP unmounted"
echo "DONE - restart the T15 (Apple menu > Restart), pick 'Macintosh HD (external)'."
