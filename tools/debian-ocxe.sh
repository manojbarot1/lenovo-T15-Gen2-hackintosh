#!/bin/bash
# Run on the T15 under Debian after: scp -r EFI/OCXE manojb@192.168.1.17:ocxe-src
#   ssh manojb@192.168.1.17 "bash -s -- SERIAL MLB" < tools/debian-ocxe.sh
# Installs EFI\OCXE (WhateverXe test, MacBookPro16,2) next to EFI\OC and EFI\OCREC on the
# external SSD's ESP, and adds the GRUB entry "macOS Ventura - Iris Xe test (external SSD)".
# EFI\OC and EFI\OCREC are not touched. Remove the test: delete EFI\OCXE and its GRUB entry.
set -euo pipefail
SERIAL=${1:?serial}; MLB=${2:?mlb}; ROM=$(tr -d ':\n' < "$(ls -d /sys/class/net/wl*/address | head -1)" | tr a-f A-F)
P=/dev/disk/by-id/ata-WD_Blue_SA510_M.2_2280_1000GB_22413B447509-part2
M=/mnt/oc
echo "--- DVMT (firmware-reserved graphics memory, from i915):"
sudo dmesg | grep -iE "stolen|DSM" | head -3 || true
sudo cat /sys/kernel/debug/dri/0/i915_gem_stolen 2>/dev/null | head -2 || true

sudo fsck.vfat -a "$P" | tail -1 || true
sudo mkdir -p $M; mountpoint -q $M || sudo mount "$P" $M
trap 'sync; sudo umount $M 2>/dev/null || true' EXIT
E=$M/EFI
sudo rm -rf $E/OCXE
sudo cp -r $E/OC $E/OCXE
sudo rm -f $E/OCXE/config.plist.before-*
sudo cp -r ~/ocxe-src/. $E/OCXE/
UUID=$(tr a-f A-F < /proc/sys/kernel/random/uuid)
sudo python3 -I - "$SERIAL" "$MLB" "$ROM" "$UUID" $E/OCXE/config.plist <<'PY'
import plistlib, sys
serial, mlb, rom, uuid, p = sys.argv[1:]
c = plistlib.load(open(p, "rb")); g = c["PlatformInfo"]["Generic"]
g["SystemSerialNumber"], g["MLB"], g["SystemUUID"], g["ROM"] = serial, mlb, uuid, bytes.fromhex(rom)
plistlib.dump(c, open(p, "wb"))
print(p, g["SystemProductName"], serial, mlb, uuid)
print("kexts:", [k["BundlePath"] for k in c["Kernel"]["Add"] if k["Enabled"]])
PY
ls $E $E/OCXE/Kexts
df -h $M | tail -1

G=/etc/grub.d/40_custom; B=/etc/grub-backups/40_custom.before-ocxe
sudo mkdir -p /etc/grub-backups; [ -f $B ] || sudo cp $G $B
grep -q "Iris Xe test" $G || sudo tee -a $G >/dev/null <<'EOF'
menuentry "macOS Ventura - Iris Xe test (external SSD)" --class macosx --class os {
	insmod part_gpt
	insmod fat
	insmod chain
	# EXPERIMENTAL: OpenCore in EFI\OCXE (WhateverXe, MacBookPro16,2, SIP 0x803)
	search --no-floppy --fs-uuid --set=root C9E9-9FEC
	chainloader /EFI/OCXE/OpenCore.efi
}
EOF
sudo update-grub 2>&1 | tail -1
sudo grep -E "^menuentry|chainloader" /boot/grub/grub.cfg | cut -c1-70
echo DONE
