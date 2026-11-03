# macOS Ventura on a ThinkPad T15 Gen 2i (OpenCore)

A record of getting macOS Ventura 13.7.8 running on a Lenovo ThinkPad T15 Gen 2i
with OpenCore 1.0.8: what was tried, what failed and why, and the procedure that
finally worked. Work done 2026-11-02 → 2026-11-03.

> **Status (2026-11-03):** macOS Ventura 13.7.8 is installed on an external USB-C SSD
> and boots to the desktop; SSH (key login) works. Graphics stay unaccelerated
> (no macOS driver for Iris Xe). Post-install steps are listed under
> [Still to do](#still-to-do).

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
| Audio | Realtek ALC257 on Tiger Lake HDA (A0C8) | AppleALC, layout-id 11: speakers ✅ |
| Bluetooth | Intel AX201 (USB 8087:0026 on HS07) | IntelBluetoothFirmware + IntelBTPatcher, BlueToolFixup 2.7.3 with the A2DP fix: AirPods Pro connect and play sound ✅ |
| Ethernet | Intel I219 | IntelMausi |
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

## 3. EFI summary (`EFI/OC/config.plist`)

| Area | Setting | Why |
|---|---|---|
| SMBIOS | `MacPro7,1` | works with the CPUID spoof and an unaccelerated iGPU (from the ThinkPad X1 Carbon Gen 9 Tiger Lake reference config) |
| CPU | `Kernel → Emulate → Cpuid1Data EB060900…`, mask `FFFFFFFF…` | Tiger Lake isn't a native macOS CPU; spoof as Coffee Lake. Without it: hang at `EXITBS:START` |
| Booter quirks | `DevirtualiseMmio`, `RebuildAppleMemoryMap`, `SyncRuntimePermissions`, `ProtectUefiServices`, `SetupVirtualMap`, `ProvideCustomSlide`, `AvoidRuntimeDefrag`, `EnableSafeModeSlide`, `FixupAppleEfiImages` | standard set for 10th–11th gen laptops |
| Kernel quirks | `AppleXcpmCfgLock`, `AppleCpuPmCfgLock`, `AppleXcpmExtraMsrs`, `DisableIoMapper`, `DisableLinkeditJettison`, `PanicNoKextDump`, `PowerTimeoutKernelPanic`, `SetApfsTrimTimeout = 0` | CFG lock can't be disabled in the Lenovo BIOS; TRIM off was a PM981 attempt (harmless now) |
| ACPI | `SSDT-AWAC-DISABLE`, `SSDT-PLUG`, `SSDT-PMC`, `SSDT-RHUB` | RTC, CPU power management, NVRAM, USB hub reset. **No** `SSDT-EC-USBX`: the T15 already has a real EC (`AE_ALREADY_EXISTS`) |
| Kexts | Lilu, VirtualSMC, CpuTscSync, WhateverGreen, NVMeFix, VoodooPS2 (+Input, Keyboard, Mouse, Trackpad), IntelMausi, itlwm 2.3.0, USBMap | CpuTscSync fixed random stalls; NVMeFix was a PM981 attempt |
| DeviceProperties | `PciRoot(0x0)/Pci(0x6,0x0)/Pci(0x0,0x0)`: `class-code = FFFFFFFF`, `name = #nvme-hidden`, `ps-max-latency-us = 0` | **hides the PM981 from macOS**, so the NVMe driver never attaches and can't panic |
| boot-args | `-v keepsyms=1 debug=0x100 -igfxvesa` | verbose boot; panics stay on screen; VESA graphics |
| csr-active-config | `00080000` | allows an unauthenticated root (set while chasing a "waiting for root device"; probably not needed, see timeline) |
| Security | `SecureBootModel = Disabled`, `ScanPolicy = 0`, `DmgLoading = Signed` | |
| Boot | `HideAuxiliary = false`, `Timeout = 0` | so the Recovery `(dmg)` entries are visible |
| UEFI | OpenRuntime, OpenHfsPlus; `Resolution = Max`, `ProvideConsoleGop` | |
| PlatformInfo | serial/MLB are **placeholders** | generate real ones with `macserial` before any Apple ID sign-in |

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

---

## Still to do

- [x] Finish setup assistant (local account, no Apple ID yet)
- [x] Turn on **Remote Login** (SSH) in macOS
- [x] UI speed-ups: `tools/mac-ui-speedup.sh` (animations off) + Reduce motion/transparency
- [x] Native Wi-Fi menu: AirportItlwm (Ventura build) enabled, itlwm disabled (applied
      from Debian; backup `config.plist.before-airportitlwm`). Works: loads on
      IO80211FamilyLegacy with `SecureBootModel` Disabled, joins via the Wi-Fi menu.
      macOS can't mount the ESP over SSH (TCC), and refused it while the FAT dirty bit
      was set; `fsck.vfat -a` from Debian fixed that.
- [x] Debian GRUB entries **"macOS Ventura (external SSD)"** and **"macOS Recovery
      (external SSD)"** (`tools/debian-oc-direct.sh`): chainload `EFI/OC/OpenCore.efi` and
      `EFI/OCREC/OpenCore.efi` on the OPENCORE ESP (fs UUID `C9E9-9FEC`). No picker:
      `ShowPicker` false and a ScanPolicy that leaves exactly one entry (OC: APFS on
      USB/SATA/SCSI, `0x250103`; OCREC: ESP only, `0x250403`, i.e. the 13.4.1 recovery dmg).
      Keep GRUB backups out of `/etc/grub.d` (executable copies there become menu entries).
- [ ] Reduce motion and transparency (System Settings → Accessibility → Display) to
      help the unaccelerated screen
- [x] Real SMBIOS serial/MLB/UUID/ROM: `macserial -m MacPro7,1` (run by the user), the
      serial checked as "invalid" on checkcoverage.apple.com, then written to both ESP
      configs with `tools/debian-smbios.sh`. Values are in git-ignored `private/`; the repo
      config keeps placeholders.
- [ ] Sign in to Apple ID (after the new serial boots: check About This Mac)
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
- [x] Bluetooth: IntelBluetoothFirmware + IntelBTPatcher 2.4.0 and BlueToolFixup 2.7.2 after Lilu in OC + OCXE (`tools/mac-add-kexts.sh`, from macOS); AX201 BT is USB 8087:0026 on HS07, which must be internal (255) in USBMap (`tools/mac-usbmap-port.sh HS07 255`); NVRAM `bluetoothExternalDongleFailed=00`, `bluetoothInternalControllerInfo`=14×00 (also in NVRAM > Delete) and boot-arg `-btlfxallowanyaddr` per the BrcmPatchRAM README for macOS 12.4+ (`tools/mac-bt-nvram.sh`). Test: AirPods
- [x] AirPods "connected but no sound": `bluetoothd` logs `Server.A2DP: Failed to read BT clock` (Intel controllers don't answer `HCI_Read_Clock`, so the A2DP fast-connect path aborts). Fix: BlueToolFixup **2.7.3** from [hexxyan/BlueToolFixup-FixA2DP](https://github.com/hexxyan/BlueToolFixup-FixA2DP/releases/tag/2.7.3) (CI-built from the head of [acidanthera/BrcmPatchRAM#38](https://github.com/acidanthera/BrcmPatchRAM/pull/38)) plus boot-arg `-btlfxa2dpcheck`, which patches the 12/13 gate `85 DB 74 25` → `31 DB EB 25` in `bluetoothd` (`tools/mac-add-kexts.sh BlueToolFixup.kext`, `tools/mac-bootarg-add.sh -btlfxa2dpcheck`). Reported working on 13.7.8 22H730 with AX200 in [IntelBluetoothFirmware#462](https://github.com/OpenIntelWireless/IntelBluetoothFirmware/issues/462). No-reboot fallback: Audio MIDI Setup → AirPods → 8 kHz, then back to 48 kHz while audio plays
- [ ] `git init` and push to GitHub (see `.gitignore`)

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

ESP edits: from macOS over SSH once Remote Login has "Allow full disk access for remote users" on (`tools/mac-*.sh`, PlistBuddy only, no Python on macOS); otherwise from Debian (`tools/debian-*.sh`). Real
serials are written to the ESP by `tools/debian-smbios.sh` / `tools/debian-ocxe.sh`.
