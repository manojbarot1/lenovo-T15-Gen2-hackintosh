#!/bin/bash
# Run on the T15 under Debian after copying RestrictEvents.kext to ~/re/:
#   scp -r kexts/RestrictEvents/x/RestrictEvents.kext manojb@192.168.1.17:re/
#   ssh manojb@192.168.1.17 'bash -s' < tools/debian-restrictevents.sh
# Adds acidanthera RestrictEvents (Lilu plugin) to both OpenCore folders on the external SSD.
# Default revblock=auto blocks the MacPro7,1 "memory modules misconfigured" / PCIe notices.
# Backups: config.plist.before-restrictevents.
set -euo pipefail
P=/dev/disk/by-id/ata-WD_Blue_SA510_M.2_2280_1000GB_22413B447509-part2
M=/mnt/oc
sudo fsck.vfat -a "$P" | tail -1 || true
sudo mkdir -p $M; mountpoint -q $M || sudo mount "$P" $M
trap 'sync; sudo umount $M 2>/dev/null || true' EXIT
for R in OC OCREC; do
  C=$M/EFI/$R/config.plist
  [ -f $C.before-restrictevents ] || sudo cp $C $C.before-restrictevents
  sudo rm -rf $M/EFI/$R/Kexts/RestrictEvents.kext
  sudo cp -r ~/re/RestrictEvents.kext $M/EFI/$R/Kexts/
done
sudo python3 -I - $M/EFI/OC/config.plist $M/EFI/OCREC/config.plist <<'PY'
import plistlib, sys
for p in sys.argv[1:]:
    c = plistlib.load(open(p, "rb")); A = c["Kernel"]["Add"]
    A[:] = [k for k in A if k["BundlePath"] != "RestrictEvents.kext"]
    i = next(n for n, k in enumerate(A) if k["BundlePath"] == "Lilu.kext") + 1
    A.insert(i, {"Arch": "Any", "BundlePath": "RestrictEvents.kext",
                 "Comment": "Hide MacPro7,1 memory/PCIe notices", "Enabled": True,
                 "ExecutablePath": "Contents/MacOS/RestrictEvents", "MaxKernel": "",
                 "MinKernel": "", "PlistPath": "Contents/Info.plist"})
    plistlib.dump(c, open(p, "wb"))
    print(p, [k["BundlePath"] for k in A if k["Enabled"]][:3], "...")
PY
echo DONE
