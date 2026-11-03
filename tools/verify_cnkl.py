"""Verify a file against an Apple chunklist (CNKL), e.g. BaseSystem.chunklist or
InstallAssistant.pkg.integrityDataV1.

usage: python3 -I verify_cnkl.py <data file> <chunklist file>

CNKL layout: magic "CNKL", u32 header size, u8 version, u8 chunk method,
u8 signature method, u8 pad, u64 chunk count, u64 chunk offset, u64 signature
offset; each chunk entry is u32 size + 32-byte SHA-256.
"""
import hashlib, os, struct, sys

data_path, cnkl_path = sys.argv[1], sys.argv[2]
raw = open(cnkl_path, "rb").read()
magic, hsize, ver, cmeth, smeth, _pad, count, coff, soff = struct.unpack("<4sIBBBBQQQ", raw[:36])
assert magic == b"CNKL", f"not a chunklist: {magic!r}"

bad = 0
total = 0
with open(data_path, "rb") as f:
    for i in range(count):
        size, digest = struct.unpack("<I32s", raw[coff + i * 36: coff + (i + 1) * 36])
        chunk = f.read(size)
        total += len(chunk)
        if len(chunk) != size or hashlib.sha256(chunk).digest() != digest:
            bad += 1
            print(f"chunk {i}: MISMATCH")
    trailing = f.read(1) != b""

print(f"{data_path}: chunks {count}, bytes {total}, bad {bad}, trailing {trailing}")
sys.exit(1 if bad or trailing or total != os.path.getsize(data_path) else 0)
