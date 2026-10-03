"""Minimal read-only local CASC reader: extract named files from a WoW install.

Usage: python scripts/extract-casc-files.py <product> <outdir> <path> [<path> ...]
  product: .build.info Product (wow_classic_beta = WoW Forever, wow_anniversary = TBC Anniversary)
  paths:   e.g. interface/icons/inv_sidetab_reputation2_c60.blp

Reads the local install only (WOW below); never writes into the game folder. Decodes BLTE
(raw / zlib chunks); encrypted chunks are reported, not decrypted. See docs/UI_DESIGN.md.
"""
import os
import struct
import sys
import zlib

WOW = r"C:\Program Files (x86)\World of Warcraft"
DATA = os.path.join(WOW, "Data")


# ---------------------------------------------------------------- build info
def build_key(product):
    with open(os.path.join(WOW, ".build.info"), encoding="utf-8") as f:
        lines = [l.rstrip("\n") for l in f if l.strip()]
    cols = [c.split("!")[0] for c in lines[0].split("|")]
    for line in lines[1:]:
        row = dict(zip(cols, line.split("|")))
        if row.get("Product") == product and row.get("Active") == "1":
            return row["Build Key"], row["Version"]
    raise SystemExit("product not found: " + product)


def read_config(key):
    p = os.path.join(DATA, "config", key[0:2], key[2:4], key)
    cfg = {}
    with open(p, encoding="utf-8") as f:
        for line in f:
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.split()
    return cfg


# ---------------------------------------------------------------- local index
def bucket_of(ekey9):
    b = 0
    for x in ekey9:
        b ^= x
    return (b & 0x0F) ^ (b >> 4)


_idx_files = None


def idx_files():
    global _idx_files
    if _idx_files is None:
        best = {}
        for name in os.listdir(os.path.join(DATA, "data")):
            if name.endswith(".idx") and len(name) == 14:
                b = int(name[0:2], 16)
                ver = int(name[2:10], 16)
                if b not in best or ver > best[b][0]:
                    best[b] = (ver, name)
        _idx_files = {b: os.path.join(DATA, "data", n) for b, (_, n) in best.items()}
    return _idx_files


def index_lookup(ekey):
    k9 = ekey[:9]
    path = idx_files()[bucket_of(k9)]
    with open(path, "rb") as f:
        data = f.read()
    header_size = struct.unpack_from("<I", data, 0)[0]
    (_ver, _bucket, _extra, size_len, off_len, key_len, off_bits) = struct.unpack_from("<HBBBBBB", data, 8)
    pos = (8 + header_size + 0x0F) & ~0x0F
    entries_size = struct.unpack_from("<I", data, pos)[0]
    pos += 8
    entry_len = key_len + off_len + size_len
    end = pos + entries_size
    while pos + entry_len <= end:
        if data[pos:pos + key_len] == k9:
            raw = int.from_bytes(data[pos + key_len:pos + key_len + off_len], "big")
            size = int.from_bytes(data[pos + key_len + off_len:pos + entry_len], "little")
            archive = raw >> off_bits
            offset = raw & ((1 << off_bits) - 1)
            return archive, offset, size
        pos += entry_len
    raise KeyError("ekey not in local index: " + ekey.hex())


# ---------------------------------------------------------------- BLTE
def blte_decode(buf):
    if buf[:4] != b"BLTE":
        raise ValueError("not BLTE")
    header_size = struct.unpack_from(">I", buf, 4)[0]
    chunks = []
    if header_size == 0:
        chunks.append((len(buf) - 8, None))
        pos = 8
    else:
        count = int.from_bytes(buf[9:12], "big")
        p = 12
        for _ in range(count):
            csize, dsize = struct.unpack_from(">II", buf, p)
            chunks.append((csize, dsize))
            p += 24
        pos = header_size
    out = bytearray()
    for csize, _dsize in chunks:
        chunk = buf[pos:pos + csize]
        pos += csize
        mode = chunk[:1]
        if mode == b"N":
            out += chunk[1:]
        elif mode == b"Z":
            out += zlib.decompress(chunk[1:])
        elif mode == b"E":
            raise ValueError("encrypted chunk (needs TACT key)")
        else:
            raise ValueError("unsupported BLTE mode %r" % mode)
    return bytes(out)


def read_ekey(ekey):
    archive, offset, size = index_lookup(ekey)
    with open(os.path.join(DATA, "data", "data.%03d" % archive), "rb") as f:
        f.seek(offset + 0x1E)
        return blte_decode(f.read(size - 0x1E))


# ---------------------------------------------------------------- encoding
class Encoding:
    def __init__(self, data):
        assert data[:2] == b"EN"
        self.data = data
        ckey_len, ekey_len = data[3], data[4]
        ce_page_kb = struct.unpack_from(">H", data, 5)[0]
        ce_pages = struct.unpack_from(">I", data, 9)[0]
        espec_size = struct.unpack_from(">I", data, 18)[0]
        self.ckey_len, self.ekey_len = ckey_len, ekey_len
        self.page_size = ce_page_kb * 1024
        p = 22 + espec_size
        self.first_keys = []
        for _ in range(ce_pages):
            self.first_keys.append(data[p:p + ckey_len])
            p += ckey_len + 16
        self.pages_start = p

    def ekey_for(self, ckey):
        # Pages are sorted by first key; last page whose first key <= ckey.
        lo, hi = 0, len(self.first_keys) - 1
        page = 0
        while lo <= hi:
            mid = (lo + hi) // 2
            if self.first_keys[mid] <= ckey:
                page = mid
                lo = mid + 1
            else:
                hi = mid - 1
        d = self.data
        p = self.pages_start + page * self.page_size
        end = p + self.page_size
        while p < end:
            count = d[p]
            if count == 0:
                break
            ck = d[p + 6:p + 6 + self.ckey_len]
            first_ekey = d[p + 6 + self.ckey_len:p + 6 + self.ckey_len + self.ekey_len]
            if ck == ckey:
                return first_ekey
            p += 6 + self.ckey_len + count * self.ekey_len
        raise KeyError("ckey not in encoding: " + ckey.hex())


# ---------------------------------------------------------------- root (MFST)
def rot(x, k):
    return ((x << k) | (x >> (32 - k))) & 0xFFFFFFFF


def hashlittle2(data, pc=0, pb=0):
    """Bob Jenkins lookup3 hashlittle2, as used for WoW root name hashes."""
    length = len(data)
    a = b = c = (0xDEADBEEF + length + pc) & 0xFFFFFFFF
    c = (c + pb) & 0xFFFFFFFF
    i = 0
    while length > 12:
        a = (a + int.from_bytes(data[i:i + 4], "little")) & 0xFFFFFFFF
        b = (b + int.from_bytes(data[i + 4:i + 8], "little")) & 0xFFFFFFFF
        c = (c + int.from_bytes(data[i + 8:i + 12], "little")) & 0xFFFFFFFF
        a = (a - c) & 0xFFFFFFFF; a ^= rot(c, 4); c = (c + b) & 0xFFFFFFFF
        b = (b - a) & 0xFFFFFFFF; b ^= rot(a, 6); a = (a + c) & 0xFFFFFFFF
        c = (c - b) & 0xFFFFFFFF; c ^= rot(b, 8); b = (b + a) & 0xFFFFFFFF
        a = (a - c) & 0xFFFFFFFF; a ^= rot(c, 16); c = (c + b) & 0xFFFFFFFF
        b = (b - a) & 0xFFFFFFFF; b ^= rot(a, 19); a = (a + c) & 0xFFFFFFFF
        c = (c - b) & 0xFFFFFFFF; c ^= rot(b, 4); b = (b + a) & 0xFFFFFFFF
        length -= 12
        i += 12
    if length == 0:
        return (c << 32) | b
    tail = data[i:] + b"\0" * (12 - length)
    a = (a + int.from_bytes(tail[0:4], "little")) & 0xFFFFFFFF
    b = (b + int.from_bytes(tail[4:8], "little")) & 0xFFFFFFFF
    c = (c + int.from_bytes(tail[8:12], "little")) & 0xFFFFFFFF
    c ^= b; c = (c - rot(b, 14)) & 0xFFFFFFFF
    a ^= c; a = (a - rot(c, 11)) & 0xFFFFFFFF
    b ^= a; b = (b - rot(a, 25)) & 0xFFFFFFFF
    c ^= b; c = (c - rot(b, 16)) & 0xFFFFFFFF
    a ^= c; a = (a - rot(c, 4)) & 0xFFFFFFFF
    b ^= a; b = (b - rot(a, 14)) & 0xFFFFFFFF
    c ^= b; c = (c - rot(b, 24)) & 0xFFFFFFFF
    return (c << 32) | b


def name_hash(path):
    return hashlittle2(path.replace("/", "\\").upper().encode("ascii"))


def root_lookup(root, wanted):
    """wanted: {name_hash: path}. Returns {path: (fileDataID, ckey)}."""
    found = {}
    if root[:4] not in (b"MFST", b"TSFM"):
        raise ValueError("unexpected root magic %r" % root[:4])
    first, second = struct.unpack_from("<II", root, 4)
    if first < 100:  # new header: headerSize, version, total, named
        header_size, version = first, second
        total, named = struct.unpack_from("<II", root, 12)
        pos = header_size
    else:
        version, total, named = 0, first, second
        pos = 12
    allow_unnamed = total != named
    while pos < len(root):
        if version >= 2:
            count, _locale, f1, f2 = struct.unpack_from("<IIII", root, pos)
            f3 = root[pos + 16]
            content = f1 | f2 | (f3 << 17)
            pos += 17
        else:
            count, content, _locale = struct.unpack_from("<III", root, pos)
            pos += 12
        ids = struct.unpack_from("<%dI" % count, root, pos)
        pos += 4 * count
        ckeys_pos = pos
        pos += 16 * count
        has_names = not (allow_unnamed and (content & 0x10000000))
        fid = -1
        fids = []
        for delta in ids:
            fid += delta + 1
            fids.append(fid)
        if has_names:
            for i in range(count):
                h = struct.unpack_from("<Q", root, pos + 8 * i)[0]
                if h in wanted and wanted[h] not in found:
                    found[wanted[h]] = (fids[i], root[ckeys_pos + 16 * i:ckeys_pos + 16 * i + 16])
            pos += 8 * count
    return found


def root_lookup_ids(root, wanted_ids):
    """wanted_ids: set of fileDataIDs. Returns {fileDataID: ckey} (first locale block wins)."""
    found = {}
    first, second = struct.unpack_from("<II", root, 4)
    if first < 100:
        header_size, version = first, second
        total, named = struct.unpack_from("<II", root, 12)
        pos = header_size
    else:
        version, total, named = 0, first, second
        pos = 12
    allow_unnamed = total != named
    while pos < len(root):
        if version >= 2:
            count, _locale, f1, f2 = struct.unpack_from("<IIII", root, pos)
            content = f1 | f2 | (root[pos + 16] << 17)
            pos += 17
        else:
            count, content, _locale = struct.unpack_from("<III", root, pos)
            pos += 12
        ids = struct.unpack_from("<%dI" % count, root, pos)
        pos += 4 * count
        fid = -1
        for i, delta in enumerate(ids):
            fid += delta + 1
            if fid in wanted_ids and fid not in found:
                found[fid] = root[pos + 16 * i:pos + 16 * i + 16]
        pos += 16 * count
        if not (allow_unnamed and (content & 0x10000000)):
            pos += 8 * count
    return found


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--ids":
        # python extract-casc-files.py --ids <product> <outdir> <idsfile>  (one fileDataID per line)
        product, outdir = sys.argv[2], sys.argv[3]
        with open(sys.argv[4]) as f:
            wanted = {int(l) for l in f if l.strip()}
        cfg = read_config(build_key(product)[0])
        enc = Encoding(read_ekey(bytes.fromhex(cfg["encoding"][1])))
        root = read_ekey(enc.ekey_for(bytes.fromhex(cfg["root"][0])))
        os.makedirs(outdir, exist_ok=True)
        for fid, ckey in sorted(root_lookup_ids(root, wanted).items()):
            try:
                blob = read_ekey(enc.ekey_for(ckey))
            except (KeyError, ValueError) as err:
                print("skip", fid, err)
                continue
            with open(os.path.join(outdir, "%d.blp" % fid), "wb") as f:
                f.write(blob)
        return
    product, outdir, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
    bkey, version = build_key(product)
    print("product", product, "build", version)
    cfg = read_config(bkey)
    enc = Encoding(read_ekey(bytes.fromhex(cfg["encoding"][1])))
    root = read_ekey(enc.ekey_for(bytes.fromhex(cfg["root"][0])))
    wanted = {name_hash(p): p for p in paths}
    found = root_lookup(root, wanted)
    os.makedirs(outdir, exist_ok=True)
    for p in paths:
        if p not in found:
            print("NOT FOUND", p)
            continue
        fid, ckey = found[p]
        blob = read_ekey(enc.ekey_for(ckey))
        out = os.path.join(outdir, os.path.basename(p))
        with open(out, "wb") as f:
            f.write(blob)
        print("extracted", p, "fileDataID", fid, len(blob), "bytes ->", out)


if __name__ == "__main__":
    main()
