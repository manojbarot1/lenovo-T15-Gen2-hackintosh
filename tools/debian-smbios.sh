#!/bin/bash
# Run on the T15 under Debian: writes a real SMBIOS identity (from macserial, checked as
# "not valid" on checkcoverage.apple.com) into both OpenCore configs on the external SSD.
#   ssh manojb@192.168.1.17 'bash -s' -- SERIAL MLB < tools/debian-smbios.sh
# ROM = the Wi-Fi card's MAC (read from the Debian wl* interface); SystemUUID = a new random UUID on every
# run, so run it once. The repo's master config keeps placeholders; real values are only
# on the ESP and in the git-ignored private/smbios.txt on the build machine.
set -euo pipefail
SERIAL=${1:?serial}; MLB=${2:?mlb}; ROM=$(tr -d ':\n' < "$(ls -d /sys/class/net/wl*/address | head -1)" | tr a-f A-F)
P=/dev/disk/by-id/ata-WD_Blue_SA510_M.2_2280_1000GB_22413B447509-part2
M=/mnt/oc
sudo fsck.vfat -a "$P" | tail -1 || true
sudo mkdir -p $M; mountpoint -q $M || sudo mount "$P" $M
trap 'sync; sudo umount $M 2>/dev/null || true' EXIT
for C in $M/EFI/OC/config.plist $M/EFI/OCREC/config.plist; do
  [ -f $C.before-smbios ] || sudo cp $C $C.before-smbios
done
UUID=$(cat /proc/sys/kernel/random/uuid | tr a-f A-F)
sudo python3 -I - "$SERIAL" "$MLB" "$ROM" "$UUID" $M/EFI/OC/config.plist $M/EFI/OCREC/config.plist <<'PY'
import plistlib, sys
serial, mlb, rom, uuid, *paths = sys.argv[1:]
for p in paths:
    c = plistlib.load(open(p, "rb")); g = c["PlatformInfo"]["Generic"]
    g["SystemSerialNumber"], g["MLB"], g["SystemUUID"], g["ROM"] = serial, mlb, uuid, bytes.fromhex(rom)
    plistlib.dump(c, open(p, "wb"))
    print(p, g["SystemProductName"], g["SystemSerialNumber"], g["MLB"], g["SystemUUID"], g["ROM"].hex())
PY
echo DONE
