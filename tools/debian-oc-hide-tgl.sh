#!/bin/bash
# Run on the T15 under Debian:  ssh manojb@192.168.1.17 'bash -s' < tools/debian-oc-hide-tgl.sh
# Keeps the VESA entry (EFI\OC, MacPro7,1) bootable after WhateverXe Graphics is installed.
# The TGL drivers in /Library/Extensions (AuxKC) load for every entry; without WhateverXe the
# framebuffer panics in AppleIntelFramebufferController::getPlatformID -> boot loop. They match
# on IOPCIPrimaryMatch 0x9a498086, so EFI\OC gets a dummy iGPU device-id (0x1234) and they never
# attach; macOS then uses the plain boot framebuffer as before. EFI\OCXE is not touched.
# Backup: EFI/OC/config.plist.before-hide-tgl
set -euo pipefail
P=/dev/disk/by-id/ata-WD_Blue_SA510_M.2_2280_1000GB_22413B447509-part2
M=/mnt/oc
sudo fsck.vfat -a "$P" | tail -1 || true
sudo mkdir -p $M; mountpoint -q $M || sudo mount "$P" $M
trap 'sync; sudo umount $M 2>/dev/null || true' EXIT
C=$M/EFI/OC/config.plist
[ -f $C.before-hide-tgl ] || sudo cp $C $C.before-hide-tgl
sudo python3 -I - $C <<'PY'
import plistlib, sys
p = sys.argv[1]; c = plistlib.load(open(p, "rb"))
d = c["DeviceProperties"]["Add"].setdefault("PciRoot(0x0)/Pci(0x2,0x0)", {})
d["device-id"] = bytes.fromhex("34120000")
plistlib.dump(c, open(p, "wb"))
print(p, {k: {n: v.hex() for n, v in props.items()} for k, props in c["DeviceProperties"]["Add"].items()})
PY
echo DONE
