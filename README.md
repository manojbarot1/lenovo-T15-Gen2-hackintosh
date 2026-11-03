# macOS Ventura on a ThinkPad T15 Gen 2i (OpenCore)

A record of getting macOS Ventura 13.7.8 running on a Lenovo ThinkPad T15 Gen 2i
with OpenCore 1.0.8: what was tried, what failed and why, and the procedure that
finally worked. Work done 2026-11-02 → 2026-11-03.

> **Status (2026-11-03, evening):** macOS Ventura 13.7.8 runs from an external USB-C SSD,
> booted straight from Debian's GRUB menu (no OpenCore picker). Working: Wi-Fi (native menu),
> Bluetooth, AirPods Pro with sound and noise control, speakers, battery status, Apple ID /
> iCloud, SSH, and **accelerated Iris Xe graphics** (Metal 2) in the `EFI/OCXE` entry.
> Not yet: screen brightness, sleep/wake (untested). See [Daily use and workarounds](#daily-use-and-workarounds)
> and [Still to do](#still-to-do).

---

## 1. Hardware

| Part | Detail | macOS status |
|---|---|---|
| Laptop | ThinkPad T15 Gen 2i (20W5S1FL1Z), BIOS N34ET72W 1.72 | — |
| CPU | Intel Core i7-1185G7 (Tiger Lake) | works with a Coffee Lake CPUID spoof |
| iGPU | Iris Xe (Tiger Lake, 0x9A49, 96 EU) | **accelerated** (Metal 2, 1536 MB, HEVC) with WhateverXe 0.7.0 + WhateverXe Graphics 0.4.0 in the `EFI/OCXE` test entry; the main entry still uses VESA (`-igfxvesa`) |
| Internal SSD | Samsung PM981 `MZVLB512HBJQ-000L7`, fw `5M2QEXF7` (latest) | **unsupported**: panics/freezes macOS; hidden from macOS |
| macOS disk | WD Blue SA510 1 TB M.2 SATA in a Satechi USB-C enclosure (10 Gbps) | works |
| Wi-Fi | Intel AX201 | `AirportItlwm` 2.3.0 Ventura build: native Wi-Fi menu (itlwm kept, disabled) |
| Trackpad / TrackPoint | Synaptics over PS/2 | VoodooPS2 (Mouse + Trackpad plugins) |
| Display backlight | eDP panel | **no brightness control yet** (no `AppleBacklightDisplay`) |
| Camera | Integrated UVC camera (USB 5986:2130) | detected; not yet tested in an app |
| Fingerprint reader | Synaptics 06cb:00bd (Prometheus, match-on-chip) | **never** on macOS: no driver, and Touch ID needs Apple's Secure Enclave. Works in Debian with `fprintd` |
| Thunderbolt 4 | Tiger Lake TB4 | not seen by macOS ("No hardware was found"); USB-C works as USB |
| Audio | Realtek ALC257 on Tiger Lake HDA (A0C8) | AppleALC, layout-id 11: speakers ✅ |
| Bluetooth | Intel AX201 (USB 8087:0026 on HS07) | IntelBluetoothFirmware + IntelBTPatcher, BlueToolFixup 2.7.3 with the A2DP fix: AirPods Pro connect and play sound; Noise Cancellation / Transparency switch from the Sound menu ✅ (Adaptive needs Sonoma+) |
| Battery | ThinkPad embedded controller | SMCBatteryManager + ECEnabler: percentage and charging ✅ |
| Ethernet | Intel I219 | IntelMausi |
| Sensors | CPU | SMCProcessor (CPU temperature for apps like Stats/iStat) |
| Build machine | ThinkPad T14 Gen 1 running Linux (this repo) | — |

The internal Samsung keeps Debian (dual boot). macOS lives on the external SSD.

---

## 2. Final layout

### External SSD (WD SA510, GPT)

| # | Name | Size | Type | Contents |
|---|---|---|---|---|
| 1 | Manoj Backu | 632 GB | exFAT | personal backup data (not touched by macOS) |
| 2 | OPENCORE | 2 GB | EFI System (FAT32) | `EFI/` (OpenCore) + `com.apple.recovery.boot/` (Ventura 13.4.1 Recovery) |
| 3 | INSTALL | 30 GB | exFAT | `InstallVentura.pkg` (13.7.8, 12.2 GB) + `install-ventura-ssd.sh` + `logs/` |
| 4 | MACOS | 267.5 GB | Apple_HFS placeholder → APFS "Macintosh HD" | macOS |

Booting: **F12 → SSD**. In the OpenCore menu, always pick entries marked **(external)**.

### Internal Samsung PM981

| Partition | Use |
|---|---|
| p1 976 MB | EFI (Debian GRUB), shows as `NO NAME` in OpenCore |
| p2 31 GB | Debian root |
| p3 25 GB | swap |
| p4 215 GB | Debian `/home` |
| p5 ~205 GB | leftover macOS attempt — **to be wiped** (see Still to do) |

---

## 3. EFI summary

Three OpenCore roots on the OPENCORE ESP, each chainloaded directly by a Debian GRUB entry
(OpenCore supports extra root folders when `OpenCore.efi` is started directly):

| | `EFI/OC` (main) | `EFI/OCXE` (Iris Xe) | `EFI/OCREC` (Recovery) |
|---|---|---|---|
| GRUB entry | macOS Ventura (external SSD) | macOS Ventura - Iris Xe test (external SSD) | macOS Recovery (external SSD) |
| SMBIOS | `MacPro7,1` | `MacBookPro16,2` | `MacPro7,1` |
| CPUID spoof | Coffee Lake `EB060900` | Ice Lake `E5060700` | Coffee Lake |
| Graphics | VESA (`-igfxvesa`); iGPU `device-id` `34120000` so the installed TGL drivers don't match and panic | WhateverXe 0.7.0 + AMFIPass 1.4.1 Mod, WhateverGreen off, `-allow3d -disablegfxfirmware -igfxdvmt`, `framebuffer-patch-enable 01000000`, `framebuffer-stolenmem 0000C003`, SSDT-PNLF | VESA |
| csr-active-config | `00080000` | `03080000` (WEX needs AMFI relaxed) | `00080000` |
| boot-args | `keepsyms=1 -igfxvesa -btlfxallowanyaddr -btlfxa2dpcheck` | `keepsyms=1 -allow3d -disablegfxfirmware -igfxdvmt -btlfxallowanyaddr -btlfxa2dpcheck` | `keepsyms=1 -igfxvesa` |
| ScanPolicy | `0x250103` (APFS on USB/SATA) | `0x250103` | `0x250403` (ESP only → the 13.4.1 recovery dmg) |
| Picker | `ShowPicker` false, `HideAuxiliary` true, `Timeout` 0 | same | `ShowPicker` false |

Common to all three:

| Area | Setting | Why |
|---|---|---|
| Booter quirks | `DevirtualiseMmio`, `RebuildAppleMemoryMap`, `SyncRuntimePermissions`, `ProtectUefiServices`, `SetupVirtualMap`, `ProvideCustomSlide`, `AvoidRuntimeDefrag`, `EnableSafeModeSlide`, `FixupAppleEfiImages` | standard set for 10th–11th gen laptops |
| Kernel quirks | `AppleXcpmCfgLock`, `AppleCpuPmCfgLock`, `AppleXcpmExtraMsrs`, `DisableIoMapper`, `DisableLinkeditJettison`, `PanicNoKextDump`, `PowerTimeoutKernelPanic`, `SetApfsTrimTimeout = 0` | CFG lock can't be disabled in the Lenovo BIOS |
| ACPI | `SSDT-AWAC-DISABLE`, `SSDT-PLUG`, `SSDT-PMC`, `SSDT-RHUB` (+ `SSDT-PNLF` in OCXE) | RTC, CPU power management, NVRAM, USB hub reset. **No** `SSDT-EC-USBX`: the T15 has a real EC (`AE_ALREADY_EXISTS`) |
| Kexts (OC order) | Lilu, BlueToolFixup 2.7.3 (A2DP fix), IntelBTPatcher, IntelBluetoothFirmware 2.4.0, AppleALC 1.9.8, RestrictEvents 1.1.6, [OCXE: WhateverXe, AMFIPass], VirtualSMC 1.3.8, SMCBatteryManager, SMCProcessor, ECEnabler 1.0.6, CpuTscSync, WhateverGreen (OC only), NVMeFix, VoodooPS2 (+Input, Keyboard, Mouse, Trackpad), IntelMausi, USBMap, AirportItlwm 2.3.0 (Ventura); itlwm present but disabled | Recovery (OCREC) has no BT/audio/battery kexts |
| DeviceProperties | `Pci(0x6,0x0)/Pci(0x0,0x0)`: `class-code = FFFFFFFF`, `name = #nvme-hidden`, `ps-max-latency-us = 0`; `Pci(0x1f,0x3)`: `layout-id = 11` | **hides the PM981**; ALC257 audio |
| NVRAM | `bluetoothExternalDongleFailed = 00`, `bluetoothInternalControllerInfo` = 14×00, both also in NVRAM > Delete | Intel Bluetooth on macOS 12.4+. OpenCore rewrites boot-args/csr/these every boot, so `nvram` from macOS doesn't stick: edit the config |
| Security | `SecureBootModel = Disabled`, `DmgLoading = Signed` | AirportItlwm needs SecureBootModel off |
| PlatformInfo | **placeholders** in git; real serial/MLB/UUID/ROM per model only on the ESP and in git-ignored `private/` | checked "invalid" on checkcoverage.apple.com before use |

### USB map (`USBMap.kext`, MacPro7,1 personalities)

| Controller | Port | Number | Connector | What |
|---|---|---|---|---|
| XHCI `0:20:0` | HS01 | 1 | USB-A | USB-A (USB 2 lane) |
| | HS03 | 3 | internal | fingerprint reader |
| | HS04 | 4 | internal | camera |
| | HS05, HS06 | 5, 6 | USB-C | USB-C (USB 2 lanes) |
| | HS07 | 7 | internal (255) | **Bluetooth** (Intel AX201, USB 8087:0026, location 0x14700000); was mapped USB-A type 3, which left macOS Bluetooth at `Address: NULL` |
| | HS10 | 10 | internal | unused (nothing enumerates here); originally guessed as Bluetooth |
| | SS01, SS02 | 13, 14 | USB-A | USB-A (USB 3 lanes) |
| TXHC `0:13:0` (Thunderbolt 4) | SS02, SS03 | 3, 4 | USB-C | USB-C (USB 3/10 Gbps lanes): **use these for the SSD** |

### Wi-Fi credentials

`itlwm.kext/Contents/Info.plist` on the **SSD/stick** contains the home SSID and
password (`WiFiConfig`). The copy in this repo's `EFI/` does **not**, and must
never be committed with them.

---

## 4. Step-by-step procedure (what works)

All commands run on the Linux build machine unless noted.

### 4.1 Get and verify the installer images

```bash
# Ventura 13.7.8 (22H730) full installer, product 093-22004 in Apple's catalog
B=https://swcdn.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4
curl -o ventura/InstallAssistant.pkg.integrityDataV1 $B/InstallAssistant.pkg.integrityDataV1
curl -C - -o ventura/InstallAssistant.pkg $B/InstallAssistant.pkg
python3 -I tools/verify_cnkl.py ventura/InstallAssistant.pkg ventura/InstallAssistant.pkg.integrityDataV1
```

Ventura 13.4.1 Recovery (`recovery/com.apple.recovery.boot/BaseSystem.dmg` +
`.chunklist`) came from `macrecovery.py` in the OpenCore package (board
`Mac-4B682C642B45593E`, `-m 00000000000000000`). Verify it the same way with
`BaseSystem.chunklist`.

### 4.2 Prepare the external SSD

1. Partition (GPT): data exFAT, 2 GB EFI System, 30 GB exFAT `INSTALL`, rest as
   **Apple HFS type `48465300-0000-11AA-AA11-00306543ECAC`** named `MACOS`.
   Don't use the Apple_APFS type for an empty partition: macOS Recovery refuses
   to erase it ("in use by APFS as physical store").
2. `mkfs.vfat -F 32 -n OPENCORE` on the EFI partition, `mkfs.exfat -L INSTALL`
   on the install partition.
3. Copy `EFI/` to OPENCORE, then put the Wi-Fi-configured `itlwm` `Info.plist`
   in place.
4. Copy `recovery/com.apple.recovery.boot/` to OPENCORE.
5. Copy `ventura/InstallAssistant.pkg` to `INSTALL/InstallVentura.pkg`, and
   `tools/install-ventura-ssd.sh` to `INSTALL/`. (12.2 GB took 41 s, against 42 min on
   a USB stick.)

### 4.3 Install

1. On the build machine: `python3 -I tools/t15link.py serve` (remote helper
   listener) and `sh tools/watch_t15.sh` (progress log, every 30 s).
2. T15: plug the SSD into a **USB-C** port → **F12** → SSD → OpenCore →
   **OPENCORE (external) (dmg)** = Ventura Recovery.
3. Recovery → Utilities → Terminal:
   ```bash
   sh /Volumes/INSTALL/install-ventura-ssd.sh
   ```
   The script:
   - starts a logger (to `INSTALL/logs`) and the remote helper (a reverse shell to the
     build machine, so progress can be checked remotely)
   - finds the single external `Apple_HFS` partition and asks for **YES**, then
     `diskutil eraseVolume APFS "Macintosh HD"` (or reuses an existing one)
   - runs `installer -pkg InstallVentura.pkg -target "/Volumes/Macintosh HD"`
   - **copies the pkg into the app as `Contents/SharedSupport/SharedSupport.dmg`**.
     In Recovery the pkg's own postinstall doesn't do this, so the app is a
     21 MB stub that waits to download 12 GB from Apple
   - runs `startosinstall --volume … --agreetolicense --nointeraction` through
     `script -q` so its output isn't buffered
4. Phase 1 reaches `Preparing: 24.5%`, verifies for a few minutes at high CPU, prints
   `Restarting… System going down for install`, and reboots.
5. **F12 → SSD → `macOS Installer (external)`**. Not the plain `macOS Installer`
   (a stale entry on the internal disk; see timeline).
6. Apple logo + progress bar → reboots → **`Macintosh HD (external)`** → setup
   assistant. **Skip Apple ID** until real serials are set.
7. If the setup assistant hangs or login spins forever, check `ls -ldO /Users` from
   Recovery. On this install `/Users` had the SIP `restricted` flag, so macOS could
   not create the home folder. Fix from **Recovery** (the installed system can't,
   even with sudo):
   ```bash
   curl -o /tmp/home.sh http://192.168.1.22:8088/home.sh && sh /tmp/home.sh
   ```
   (`tools/serve/home.sh`: `chflags norestricted`, builds `/Users/<user>` from the
   User Template, adds the build machine's SSH key.) `tools/serve/ssh.sh` turns on
   Remote Login offline in the same way. Serve both with
   `python3 -m http.server 8088` in `tools/serve`.

---

## 5. Timeline: what was tried and what happened

| # | Attempt | Result | Cause / lesson |
|---|---|---|---|
| 1 | Rebuild EFI from scratch (old stick corrupted), OC 1.0.8, Sequoia Recovery | Recovery entry missing | `HideAuxiliary` defaults to true → set false |
| 2 | Sequoia Recovery + AirportItlwm | `Invalid Parameter` | AirportItlwm build/OS mismatch → switched to `itlwm` |
| 3 | First boot | hang at `EXITBS:START` | Tiger Lake: took X1C9 settings (CPUID spoof, `DevirtualiseMmio`, MacPro7,1) |
| 4 | Recovery GUI | no external mouse/trackpad | added VoodooPS2 Mouse + Trackpad plugins |
| 5 | Recovery | USB devices missing | built a USB map + `SSDT-RHUB` |
| 6 | `SSDT-EC-USBX` | `AE_ALREADY_EXISTS` | T15 has a real EC → removed; added CpuTscSync for stalls |
| 7 | Erase internal partition to APFS on Sequoia | **froze** | first sign of the PM981 problem |
| 8 | Ventura Recovery, APST off (`ps-max-latency-us = 0`) + ASPM off | drive not found ("waiting for root device") | ASPM off breaks the PM981 → kept APST off only |
| 9 | Ventura online install on PM981 | phase 1 OK; **phase 2 panic at ~78 s**: `IONVMeController::RequestAsyncEvents` → `IOTimerEventSource::timeoutSignaled` | PM981 never answers an NVMe async-event request; NVMeFix doesn't help |
| 10 | Monterey 12.5.1 Recovery (hoping NVMeFix works better there) | hangs before the GUI (launchd lines, then nothing) | not resolved; Monterey Recovery unusable on this machine |
| 11 | Ventura Recovery + Monterey 12.7.6 offline pkg | intermittent `AppleGPUWrangler` panic at boot (once) | retry worked; VESA-only iGPU |
| 12 | Script: `diskutil eraseVolume` on the APFS physical store | "in use by APFS as physical store" | must delete the container, or start from a non-APFS partition |
| 13 | `diskutil apfs deleteContainer` on PM981 | **froze at 50%** | PM981 + heavy APFS metadata I/O |
| 14 | Wiped p5 from Linux (blkdiscard + zero), type still Apple_APFS | Recovery still refuses ("No APFS Containers found" but "in use") | diskutil won't erase an Apple_APFS-typed partition → retyped to Apple HFS from Linux |
| 15 | Monterey `startosinstall` from Ventura Recovery | "cannot be used from the version of macOS you are running" | `SYSTEM_VERSION_COMPAT=1` makes Ventura report 10.16 and gets past it |
| 16 | …then | stuck idle, wants to download | pkg postinstall skipped in Recovery → app missing `SharedSupport.dmg` → copy pkg in manually |
| 17 | …then | stuck at "Preparing to run macOS Installer…" with 0% CPU | Monterey installer from Ventura Recovery isn't viable → back to Ventura |
| 18 | Ventura 13.7.8 offline on PM981 | **froze** during pkg unpack | PM981 again |
| 19 | Retry | phase 1 complete; **phase 2 panic at 77 s** (same NVMe timeout), `Mac OS version: Not yet set` | TRIM off (`SetApfsTrimTimeout = 0`) didn't help |
| 20 | Check PM981 firmware via `fwupd` | already latest (`5M2QEXF7`) | no firmware fix exists → PM981 is a dead end |
| 21 | External WD SA510 SSD as target, PM981 hidden via `class-code FFFFFFFF` | Recovery sees **no internal disk**; phase 1 completes on the SSD in minutes | **the fix** |
| 22 | Phase 2: picked `macOS Installer` | 🚫 `Still waiting for root device`, `apfs_extract_root_hash_and_manifest failed (22)` | booted the **stale installer on the hidden PM981**; also set `csr-active-config 00080000` |
| 23 | Phase 2: picked `macOS Installer (external)` | Apple logo + progress bar | 🎉 |
| 24 | Setup assistant | hung at time zone; after a forced restart, login spun forever | — |
| 25 | Remote Login enabled offline from Recovery (`ssh.sh`) | sshd up; password login works but no home folder; `sudo mkdir /Users/manojb` → *Operation not permitted* | `/Users` had the SIP **`restricted`** flag |
| 26 | `home.sh` from Recovery: clear flag, build home, add key | login reaches the desktop; key SSH works | 🎉 |
| 27 | Iris Xe via [WhateverXe](https://github.com/b00t0x/WhateverXe) in a separate `EFI/OCXE` (`tools/build-ocxe.py`, `tools/debian-ocxe.sh`): MacBookPro16,2 + Ice Lake CPUID `0x706E5`, WEX + AMFIPass Mod after Lilu, WhateverGreen off, `-allow3d -disablegfxfirmware -igfxdvmt`, `framebuffer-stolenmem 0000C003` (DVMT is 64 MB), SIP `03080000`, SSDT-PNLF | **Metal 2**, `IntelAccelerator`, `TGLAcceleratorAdmissionReady = Yes`, 30-bit colour, HEVC | 🎉 The Graphics pkg is unsigned: Gatekeeper silently blocked the GUI install, so it went in with `sudo installer -pkg … -target /` |
| 28 | Normal (VESA) entry after the Graphics pkg | **boot loop**: panic in `AppleIntelTGLGraphicsFramebuffer` `getPlatformID` (the AuxKC drivers load for every entry; without WEX they crash) | `EFI/OC` gets iGPU `device-id` `34120000` (`tools/debian-oc-hide-tgl.sh`): TGL drivers don't match, VESA as before ✅ |
| 29 | ESP edits from macOS over SSH | `Operation not permitted` (TCC) | Remote Login → "Allow full disk access for remote users"; then `tools/mac-*.sh` with sudo + PlistBuddy, no Debian reboot ✅ |
| 30 | AppleALC 1.9.8, `layout-id` 11 (ALC257) | speakers work, Built-in Microphone listed ✅ | |
| 31 | Intel BT kexts (IntelBluetoothFirmware, IntelBTPatcher, BlueToolFixup 2.7.2) | Bluetooth `Address: NULL`, finds nothing | USBMap had HS07 (the BT device) as external type 3 → set to **255 internal** ✅ |
| 32 | …then | "unable to turn on Bluetooth" (bluetoothd power state 0) | NVRAM `bluetoothExternalDongleFailed`/`bluetoothInternalControllerInfo` + `-btlfxallowanyaddr` → Bluetooth on ✅ |
| 33 | AirPods Pro pair, show battery | **connected but no sound**; log: `Server.A2DP: Failed to read BT clock` | BlueToolFixup 2.7.3 (A2DP fix) + `-btlfxa2dpcheck` → sound ✅ |
| 34 | AirPods noise control | options "missing" | they were in the Sound menu, which was hidden: Sound/Bluetooth menu-bar icons set to always show → Noise Cancellation / Transparency ✅ |
| 35 | Battery | macOS showed no battery | SMCBatteryManager + SMCProcessor + ECEnabler after VirtualSMC → battery icon and % ✅ |

### Lessons

- **Check the disk model first.** Samsung PM981/PM991 (and Micron 2200S) don't
  work with macOS. Every software workaround (APST, NVMeFix, TRIM off, firmware)
  only moved where it failed.
- **Hiding a PCI device:** in DeviceProperties, set `class-code = FFFFFFFF` on its
  path; macOS's drivers then never match it.
- **Offline install from Recovery:** `installer -pkg InstallAssistant.pkg`, then copy the
  pkg itself to `…/Contents/SharedSupport/SharedSupport.dmg`, then run
  `startosinstall`. Pipe its output through `script -q`, not `tee`, or it's
  invisible.
- **Keep installer and Recovery the same major version.**
- **Clean up stale installs** before switching target disks: duplicate
  "macOS Installer" entries cost a reboot cycle.
- **Fast media matters:** USB stick writes ran at about 5 MB/s, the SSD at about 300 MB/s.
- **Remote visibility:** a reverse-shell helper started by the install script
  (`/dev/tcp` back to the build machine) made Recovery debuggable without photos.
  It only works in Recovery, not in installer phase 2.
- **A spinning first login can mean there's no home folder.** Check `ls -ldO /Users`
  for `restricted` and fix it from Recovery.
- **Don't keep work in `/tmp`.** A reboot wiped the first set of helper scripts.
- **Intel Bluetooth needs three things:** the BT USB port mapped *internal* (255), the two
  NVRAM keys plus `-btlfxallowanyaddr`, and (for AirPods sound) the A2DP gate patch.
- **"Missing" settings may just be hidden in a menu-bar item** that isn't shown.
- **Kext plugins go right after their parent** (`SMC*` after VirtualSMC) in Kernel > Add.
- **Installed drivers in /Library/Extensions load for every OpenCore entry.** A test entry's
  drivers can break the main entry (the TGL framebuffer panic); spoof `device-id` there.
- **Never run `python3` on macOS over SSH** without Xcode tools: it pops an install dialog on
  the user's screen. Use `plutil`/PlistBuddy.
- **Quote ssh arguments twice:** `ssh host "bash -s -- 'a b'"`, or ssh joins and re-splits them.

---

## Daily use and workarounds

**Booting.** Pick from Debian's GRUB menu: *macOS Ventura - Iris Xe test* (accelerated, the
one to use), *macOS Ventura* (VESA fallback), *macOS Recovery*. If macOS won't boot, start
Debian and restore the last `config.plist.before-<change>` backup on the ESP (mounted from
`/dev/disk/by-id/ata-WD_Blue_SA510_M.2_2280_1000GB_22413B447509-part2`).

**Changing OpenCore from macOS (no reboot into Debian):**

```bash
scp -r <kexts> tools/mac-add-kexts.sh manojb@192.168.1.17:addk/
ssh -t manojb@192.168.1.17 'sudo bash ~/addk/mac-add-kexts.sh A.kext B.kext'            # after Lilu
ssh -t manojb@192.168.1.17 'sudo AFTER=VirtualSMC.kext bash ~/addk/mac-add-kexts.sh X.kext'  # after a parent
ssh -t manojb@192.168.1.17 'sudo bash ~/addk/mac-bootarg-add.sh -someflag'
```

Each script edits both `EFI/OC` and `EFI/OCXE`, keeps a `.before-*` backup and lints the plist.
Mirror the change into this repo and push.

**AirPods Pro.**
- Noise Cancellation / Transparency: Sound icon in the menu bar → under the AirPods, or
  System Settings → "<name>'s AirPods Pro" → Noise Control. Adaptive needs Sonoma+.
- Menu-bar icons (if they disappear): `defaults -currentHost write com.apple.controlcenter Sound -int 18`,
  same for `Bluetooth`, then `killall ControlCenter`.
- If sound drops again: Audio MIDI Setup → AirPods → 1 ch 16-bit 8 kHz, then back to
  2 ch 48 kHz while something plays. Re-connecting the AirPods also helps.
- If Bluetooth ever refuses to turn on after an update: remove `-btlfxa2dpcheck` (one user
  reported this with the 2.7.3 patch).
- Codec is SBC (Intel controller), not AAC.

**Updates.** Stay on Ventura 13.7.8: turn off automatic macOS updates and ignore the Tahoe
prompt (AirportItlwm's Ventura build, the WEX graphics payloads, USB map and BT patches would break).

**Touch ID alternatives** (the reader can't work): iPhone unlock apps (Unlox/MacID, Near Lock,
over Bluetooth LE), a YubiKey as a native macOS smart card (login, unlock, `sudo`; the YubiKey Bio
Multi-protocol Edition adds a fingerprint), or a Broadcom BCM94360NG card swap for Apple Watch
unlock, AirDrop and Handoff (check the slot accepts a non-CNVi card first).

**Secrets.** Real serials live in `private/smbios.txt`; the Wi-Fi password lives in
`stick-backup/` and the ESP's itlwm Info.plist. None of it is committed; scan before each push.

---

## Still to do

- [x] Finish setup assistant (local account, no Apple ID yet)
- [x] Turn on **Remote Login** (SSH) in macOS
- [x] UI speed-ups: `tools/mac-ui-speedup.sh` (animations off) + Reduce motion/transparency
- [x] Native Wi-Fi menu: AirportItlwm (Ventura build) enabled, itlwm disabled (applied
      from Debian; backup `config.plist.before-airportitlwm`). Works: loads on
      IO80211FamilyLegacy with `SecureBootModel` Disabled, joins via the Wi-Fi menu.
      macOS couldn't mount the ESP over SSH (TCC, fixed later: timeline 29), and refused it while
      the FAT dirty bit was set; `fsck.vfat -a` from Debian fixed that.
- [x] Debian GRUB entries **"macOS Ventura (external SSD)"** and **"macOS Recovery
      (external SSD)"** (`tools/debian-oc-direct.sh`): chainload `EFI/OC/OpenCore.efi` and
      `EFI/OCREC/OpenCore.efi` on the OPENCORE ESP (fs UUID `C9E9-9FEC`). No picker:
      `ShowPicker` false and a ScanPolicy that leaves exactly one entry (OC: APFS on
      USB/SATA/SCSI, `0x250103`; OCREC: ESP only, `0x250403`, i.e. the 13.4.1 recovery dmg).
      Keep GRUB backups out of `/etc/grub.d` (executable copies there become menu entries).
- [x] Reduce motion and transparency (System Settings → Accessibility → Display) to
      help the unaccelerated screen
- [x] Real SMBIOS serial/MLB/UUID/ROM: `macserial -m MacPro7,1` (run by the user), the
      serial checked as "invalid" on checkcoverage.apple.com, then written to both ESP
      configs with `tools/debian-smbios.sh`. Values are in git-ignored `private/`; the repo
      config keeps placeholders.
- [x] Signed in to Apple ID / iCloud (Messages database created; iMessage/FaceTime still to test)
- [ ] Wipe the stale macOS partition on the Samsung (p5) from Debian, removing the
      duplicate entries; decide whether to give the space back to Debian
- [ ] Optionally hide `NO NAME`, or label it Debian via `.contentDetails`
- [ ] Decide on `csr-active-config` (try `00000000` again now the right entry is known)
- [x] Dropped `-v debug=0x100`: boot-args `keepsyms=1 -igfxvesa` (`tools/debian-bootargs.sh`)
- [x] RestrictEvents 1.1.6 after Lilu: hides the MacPro7,1 "memory modules misconfigured" notice
- [ ] Resume the backup copy-back (TEMPBACKUP → SSD partition 1, 53/290 GB done)
- [ ] Stay on Ventura 13.7.8: turn off automatic macOS updates (Tahoe would break AirportItlwm's Ventura build, WEX Graphics payloads, USB map and the offline-install path)
- [x] Audio: **Realtek ALC257** (codec 0x10EC0257) on Tiger Lake HDA 8086:A0C8 (subsystem 17AA:22C9). AppleALC 1.9.8 after Lilu in OC + OCXE, `layout-id` 11 on `Pci(0x1f,0x3)` (`tools/mac-applealc.sh`, run from macOS). Speakers work; macOS shows Built-in Microphone and Line In
- [ ] Audio: confirm headphone jack switching and the internal mic
- [x] Battery: macOS showed no battery at all (no `AppleSmartBattery`). Add VirtualSMC's SMCBatteryManager + ECEnabler (ThinkPad EC fields are wider than 8 bits). Added SMCBatteryManager + SMCProcessor (VirtualSMC 1.3.8) and ECEnabler 1.0.6 right after VirtualSMC in OC + OCXE (`AFTER=VirtualSMC.kext tools/mac-add-kexts.sh …`): battery icon and percentage show ✅
- [ ] Brightness: no `AppleBacklightDisplay`, so no slider; check SSDT-PNLF with WEX, add BrightnessKeys for the Fn keys
- [ ] Sleep/wake and lid: untested; laptop defaults `hibernatemode 0`, Power Nap off, then check USB/Wi-Fi after wake
- [x] Sensors: SMCProcessor (CPU temperature) loaded with the battery kexts
- [ ] Test the camera (UVC, detected), the built-in mic, an external display over HDMI/USB-C, iMessage/FaceTime
- [ ] Make the Iris Xe entry the default (or merge it into `EFI/OC`) after a few days of use
- Won't match a real Mac: fingerprint reader / Touch ID, AirDrop and some Continuity (Intel Wi-Fi), Sidecar, Thunderbolt hot-plug, DRM streaming (Apple TV+) on iGPU-only, Adaptive AirPods mode (Sonoma+)
- [x] Bluetooth: IntelBluetoothFirmware + IntelBTPatcher 2.4.0 and BlueToolFixup 2.7.2 after Lilu in OC + OCXE (`tools/mac-add-kexts.sh`, from macOS); AX201 BT is USB 8087:0026 on HS07, which must be internal (255) in USBMap (`tools/mac-usbmap-port.sh HS07 255`); NVRAM `bluetoothExternalDongleFailed=00`, `bluetoothInternalControllerInfo`=14×00 (also in NVRAM > Delete) and boot-arg `-btlfxallowanyaddr` per the BrcmPatchRAM README for macOS 12.4+ (`tools/mac-bt-nvram.sh`). AirPods pair
- [x] AirPods "connected but no sound": `bluetoothd` logs `Server.A2DP: Failed to read BT clock` (Intel controllers don't answer `HCI_Read_Clock`, so the A2DP fast-connect path aborts). Fix: BlueToolFixup **2.7.3** from [hexxyan/BlueToolFixup-FixA2DP](https://github.com/hexxyan/BlueToolFixup-FixA2DP/releases/tag/2.7.3) (CI-built from the head of [acidanthera/BrcmPatchRAM#38](https://github.com/acidanthera/BrcmPatchRAM/pull/38)) plus boot-arg `-btlfxa2dpcheck`, which patches the 12/13 gate `85 DB 74 25` → `31 DB EB 25` in `bluetoothd` (`tools/mac-add-kexts.sh BlueToolFixup.kext`, `tools/mac-bootarg-add.sh -btlfxa2dpcheck`). Reported working on 13.7.8 22H730 with AX200 in [IntelBluetoothFirmware#462](https://github.com/OpenIntelWireless/IntelBluetoothFirmware/issues/462). No-reboot fallback: Audio MIDI Setup → AirPods → 8 kHz, then back to 48 kHz while audio plays
- [x] Private GitHub repo `manojbarot1/t15-hackintosh`, updated after every change

---

## Repo layout

| Path | What | In git? |
|---|---|---|
| `README.md` | this document | yes |
| `EFI/BOOT`, `EFI/OC/` | OpenCore master, main entry: MacPro7,1, VESA (no Wi-Fi password, placeholder serials) | yes |
| `EFI/OCREC/` | Recovery entry: **only the files that differ** from `EFI/OC` (config, RestrictEvents); `tools/debian-oc-direct.sh` copies `EFI/OC` and overlays them | yes |
| `EFI/OCXE/` | Iris Xe entry: **overlay** on `EFI/OC` (config, WhateverXe, AMFIPass Mod, USBMap for MacBookPro16,2, SSDT-PNLF); built by `tools/build-ocxe.py`, installed by `tools/debian-ocxe.sh` | yes |
| `tools/` | install script, remote helpers, Debian-side ESP editors, macOS tweaks | yes |
| `kexts/`, `opencore/` | downloaded upstream releases (incl. WhateverXe-Graphics pkg) | no (re-downloadable) |
| `ventura/`, `monterey/`, `recovery*/` | multi-GB Apple images | no |
| `stick-backup/` | EFI copy **with Wi-Fi password** | **never** |
| `private/` | real serials/MLB/UUID/ROM for both SMBIOS models | **never** |
| `t15-backup/` | T15 fstab/home backup | no |
| `photos/` | phone photos of the T15 screen | no (local) |

### Tools

| Script | Runs on | Does |
|---|---|---|
| `install-ventura-ssd.sh`, `watch_t15.sh`, `t15link.py`, `verify_cnkl.py` | Recovery / T14 | offline install, progress watch, reverse-shell bridge, installer chunk check |
| `serve/ssh.sh`, `serve/home.sh` | Recovery (fetched over HTTP) | enable sshd offline; clear `restricted` on /Users and build the home folder |
| `t15-home.sh`, `t15-diag.sh` | T14 | drive the two above; collect diagnostics |
| `debian-oc-direct.sh` | Debian | no-picker OC/OCREC + GRUB entries |
| `debian-smbios.sh SERIAL MLB`, `debian-ocxe.sh SERIAL MLB` | Debian | real SMBIOS into OC; build/install OCXE + its GRUB entry (ROM read from the Wi-Fi MAC) |
| `debian-bootargs.sh`, `debian-restrictevents.sh`, `debian-oc-hide-tgl.sh` | Debian | boot-args; RestrictEvents; iGPU device-id spoof for the main entry |
| `build-ocxe.py` | T14 | builds `EFI/OCXE` from `EFI/OC` |
| `mac-add-kexts.sh [AFTER=X.kext]` | macOS, sudo | copy + insert kexts in OC and OCXE |
| `mac-bootarg-add.sh ARG` | macOS, sudo | append a boot-arg in OC and OCXE |
| `mac-applealc.sh`, `mac-bt-nvram.sh`, `mac-usbmap-port.sh PORT TYPE` | macOS, sudo | AppleALC + layout-id; BT NVRAM keys; one USBMap port type |
| `mac-ui-speedup.sh`, `mac-airportitlwm.sh` | macOS | animation tweaks; (superseded) AirportItlwm switch |

ESP edits: from macOS over SSH once Remote Login has "Allow full disk access for remote users" on (`tools/mac-*.sh`, PlistBuddy only, no Python on macOS); otherwise from Debian (`tools/debian-*.sh`). Real
serials are written to the ESP by `tools/debian-smbios.sh` / `tools/debian-ocxe.sh`.
