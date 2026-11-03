#!/bin/bash
# Run on the T15 under Debian (sudo, no password): makes GRUB boot straight into macOS or
# macOS Recovery, with no OpenCore picker in between.
#   ssh manojb@192.168.1.17 'bash -s' < tools/debian-oc-direct.sh
#
# EFI\OC     -> macOS:    ShowPicker off, HideAuxiliary on, ScanPolicy = APFS on USB/SATA/SCSI
#                         only (skips the hidden Samsung NVMe, Debian/Windows ESPs, Recovery)
# EFI\OCREC  -> Recovery: copy of EFI\OC, ScanPolicy = ESP on USB/SATA/SCSI only, so the one
#                         bootable entry is com.apple.recovery.boot on the OPENCORE ESP
# OpenCore supports extra root folders when OpenCore.efi is launched directly (GRUB chainload).
# Backups: EFI/OC/config.plist.before-direct-boot, /etc/grub-backups/40_custom.before-direct-boot
set -euo pipefail
P=/dev/disk/by-id/ata-WD_Blue_SA510_M.2_2280_1000GB_22413B447509-part2
M=/mnt/oc
sudo fsck.vfat -a "$P" | tail -1 || true
sudo mkdir -p $M; mountpoint -q $M || sudo mount "$P" $M
trap 'sync; sudo umount $M 2>/dev/null || true' EXIT
E=$M/EFI
[ -f $E/OC/config.plist.before-direct-boot ] || sudo cp $E/OC/config.plist $E/OC/config.plist.before-direct-boot

sudo rm -rf $E/OCREC
sudo cp -r $E/OC $E/OCREC
sudo rm -f $E/OCREC/config.plist.before-*

sudo python3 -I - "$E/OC/config.plist" "$E/OCREC/config.plist" <<'PY'
import plistlib, sys
LOCKS = 0x1 | 0x2
DEV = 0x10000 | 0x40000 | 0x200000          # SATA | SCSI | USB  (no NVMe, no PCI)
for path, fs, hide in ((sys.argv[1], 0x100, True),    # APFS
                       (sys.argv[2], 0x400, False)):  # ESP (recovery dmg is auxiliary)
    c = plistlib.load(open(path, "rb"))
    b, s = c["Misc"]["Boot"], c["Misc"]["Security"]
    b["ShowPicker"] = False
    b["HideAuxiliary"] = hide
    b["PollAppleHotKeys"] = True
    s["ScanPolicy"] = LOCKS | fs | DEV
    plistlib.dump(c, open(path, "wb"))
    print(f"{path}: ShowPicker={b['ShowPicker']} HideAuxiliary={hide} ScanPolicy=0x{s['ScanPolicy']:X}")
PY
ls $E $E/OCREC
df -h $M | tail -1

G=/etc/grub.d/40_custom; B=/etc/grub-backups/40_custom.before-direct-boot  # not in grub.d: executable copies there become menu entries
sudo mkdir -p /etc/grub-backups; [ -f $B ] || sudo cp $G $B
sudo python3 -I - $G <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'\nmenuentry "macOS[^\n]*\{.*?\n\}\n', "\n", s, flags=re.S)
for title, root in (("macOS Ventura", "OC"), ("macOS Recovery", "OCREC")):
    s += f'''menuentry "{title} (external SSD)" --class macosx --class os {{
	insmod part_gpt
	insmod fat
	insmod chain
	# OpenCore in EFI\\{root} on the WD SA510 OPENCORE ESP; needs the SSD plugged in
	search --no-floppy --fs-uuid --set=root C9E9-9FEC
	chainloader /EFI/{root}/OpenCore.efi
}}
'''
open(p, "w").write(s)
PY
sudo update-grub 2>&1 | tail -2
sudo grep -E "^menuentry|^submenu|chainloader" /boot/grub/grub.cfg | cut -c1-80
echo DONE
