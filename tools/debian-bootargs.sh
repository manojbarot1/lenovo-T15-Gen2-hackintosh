#!/bin/bash
# Run on the T15 under Debian: set boot-args in both OpenCore configs on the external SSD.
#   ssh manojb@192.168.1.17 "bash -s -- 'keepsyms=1 -igfxvesa'" < tools/debian-bootargs.sh
# (quote inside the remote command: ssh joins its args into one string, so an outer-quoted
#  "keepsyms=1 -igfxvesa" arrives as two words and -igfxvesa is lost)
# (NVRAM > Delete lists boot-args, so OpenCore rewrites it every boot; `nvram` in macOS can't
# change it.) Debug set: "-v keepsyms=1 debug=0x100 -igfxvesa" (verbose text, no auto-reboot
# on panic). Backups: config.plist.before-bootargs.
set -euo pipefail
ARGS=${1:?boot-args}
P=/dev/disk/by-id/ata-WD_Blue_SA510_M.2_2280_1000GB_22413B447509-part2
M=/mnt/oc
sudo fsck.vfat -a "$P" | tail -1 || true
sudo mkdir -p $M; mountpoint -q $M || sudo mount "$P" $M
trap 'sync; sudo umount $M 2>/dev/null || true' EXIT
for C in $M/EFI/OC/config.plist $M/EFI/OCREC/config.plist; do
  [ -f $C.before-bootargs ] || sudo cp $C $C.before-bootargs
done
sudo python3 -I - "$ARGS" $M/EFI/OC/config.plist $M/EFI/OCREC/config.plist <<'PY'
import plistlib, sys
args, *paths = sys.argv[1:]
G = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
for p in paths:
    c = plistlib.load(open(p, "rb"))
    c["NVRAM"]["Add"][G]["boot-args"] = args
    plistlib.dump(c, open(p, "wb"))
    print(p, "boot-args =", repr(c["NVRAM"]["Add"][G]["boot-args"]))
PY
echo DONE
