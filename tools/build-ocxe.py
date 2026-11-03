"""Build EFI/OCXE: an experimental OpenCore root for Iris Xe acceleration via WhateverXe.

usage: python3 -I tools/build-ocxe.py   (from the repo root)

Starts from EFI/OC/config.plist (the working VESA setup) and changes only what WhateverXe
needs, following its README and a working Tiger Lake 0x9A49 EFI
(dwiwinarno911/opencore-msi-tigerlake-irisxe):
  - SMBIOS MacBookPro16,2 (Ice Lake MBP with iGPU) + Ice Lake CPUID spoof 0x706E5
  - Lilu -> RestrictEvents -> WhateverXe -> AMFIPass; WhateverGreen disabled
  - boot-args -allow3d -disablegfxfirmware -igfxdvmt (+ framebuffer-stolenmem for 60MB DVMT)
  - csr-active-config 03080000 (0x803), required by WhateverXe Graphics
  - SSDT-PNLF for brightness; USBMap personalities re-keyed to MacBookPro16,2
Serials stay placeholders here; tools/debian-ocxe.sh writes the real ones on the ESP.
"""
import os, plistlib, shutil

SRC, DST = "EFI/OC", "EFI/OCXE"
MODEL = "MacBookPro16,2"
G = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
IGPU = "PciRoot(0x0)/Pci(0x2,0x0)"

os.makedirs(f"{DST}/Kexts", exist_ok=True)
os.makedirs(f"{DST}/ACPI", exist_ok=True)
for name, src in (("WhateverXe.kext", "kexts/WhateverXe/x/WhateverXe.kext"),
                  ("AMFIPass.kext", "kexts/AMFIPass/x/AMFIPass.kext"),
                  ("USBMap.kext", f"{SRC}/Kexts/USBMap.kext")):
    shutil.rmtree(f"{DST}/Kexts/{name}", ignore_errors=True)
    shutil.copytree(src, f"{DST}/Kexts/{name}")
shutil.copy("opencore/pkg/Docs/AcpiSamples/Binaries/SSDT-PNLF.aml", f"{DST}/ACPI/")

# USB map: same ports, personalities matched to the new model
u = f"{DST}/Kexts/USBMap.kext/Contents/Info.plist"
p = plistlib.load(open(u, "rb"))
p["IOKitPersonalities"] = {k.replace("MacPro7,1", MODEL): dict(v, model=MODEL)
                           for k, v in p["IOKitPersonalities"].items()}
plistlib.dump(p, open(u, "wb"))

c = plistlib.load(open(f"{SRC}/config.plist", "rb"))
A = c["Kernel"]["Add"]
for k in A:
    if k["BundlePath"] == "WhateverGreen.kext":
        k["Enabled"] = False
A[:] = [k for k in A if k["BundlePath"] not in ("WhateverXe.kext", "AMFIPass.kext")]
i = next(n for n, k in enumerate(A) if k["BundlePath"] == "RestrictEvents.kext") + 1
for name, comment in (("AMFIPass.kext", "AMFIPass 1.4.1 Mod (for WhateverXe Graphics)"),
                      ("WhateverXe.kext", "Iris Xe (Tiger Lake) graphics")):
    A.insert(i, {"Arch": "Any", "BundlePath": name, "Comment": comment, "Enabled": True,
                 "ExecutablePath": f"Contents/MacOS/{name[:-5]}", "MaxKernel": "",
                 "MinKernel": "", "PlistPath": "Contents/Info.plist"})

c["Kernel"]["Emulate"]["Cpuid1Data"] = bytes.fromhex("e5060700" + "00" * 12)
c["Kernel"]["Emulate"]["Cpuid1Mask"] = bytes.fromhex("ffffffff" + "00" * 12)

if not any(a["Path"] == "SSDT-PNLF.aml" for a in c["ACPI"]["Add"]):
    c["ACPI"]["Add"].append({"Comment": "Backlight (PNLF)", "Enabled": True, "Path": "SSDT-PNLF.aml"})

c["DeviceProperties"]["Add"][IGPU] = {"framebuffer-patch-enable": bytes.fromhex("01000000"),
                                      "framebuffer-stolenmem": bytes.fromhex("0000C003")}

nv = c["NVRAM"]["Add"][G]
nv["boot-args"] = "keepsyms=1 -allow3d -disablegfxfirmware -igfxdvmt"
nv["csr-active-config"] = bytes.fromhex("03080000")

gen = c["PlatformInfo"]["Generic"]
gen["SystemProductName"] = MODEL
gen["SystemSerialNumber"], gen["MLB"] = "W00000000001", "M0000000000000001"

plistlib.dump(c, open(f"{DST}/config.plist", "wb"))
print("kexts:", [k["BundlePath"] for k in A if k["Enabled"]])
print("boot-args:", nv["boot-args"], "| csr:", nv["csr-active-config"].hex(), "| model:", MODEL)
print("USBMap:", list(p["IOKitPersonalities"]))
