# Checks GS Remap's loaders of the formats MegaconvertGS added against the test pictures
# MegaconvertGS's suites make (written from known pixels, each with NAME.exp: width,
# height, RGB). Every picture GS Remap reads must give exactly those pixels.
#   python3 Tests/crosscheck/megaconvert.py [MegaconvertGS/build/fixtures]
import os, struct, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
fix = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Documents/MegaconvertGS/build/fixtures")
sc4 = os.path.join(root, ".build", "release", "sc4")
ok, done = True, 0
tmp = tempfile.mkdtemp()
for listing, folder in (("newfmt.list", "newfmt"),):
    path = os.path.join(fix, listing)
    if not os.path.exists(path): print("missing", path); sys.exit(1)
    for line in open(path):
        name, fid, *_ = line.split()
        src = os.path.join(fix, folder, name)
        out = os.path.join(tmp, name + ".rgb")
        r = subprocess.run([sc4, "load", src, out, fid], capture_output=True, text=True)
        exp = open(src + ".exp", "rb").read()
        w, h = struct.unpack("<HH", exp[:4]); want = exp[4:]
        if r.returncode:
            print(f"{name:13s} {fid:6s} FAIL: {(r.stderr or r.stdout).strip()[:90]}"); ok = False; continue
        got = open(out, "rb").read()
        if got == want: status = "OK"
        elif len(got) != len(want): status = f"FAIL: {len(got)} bytes, not {len(want)} ({r.stdout.strip()})"
        else:
            n = sum(a != b for a, b in zip(got, want))
            i = next(k for k, (a, b) in enumerate(zip(got, want)) if a != b) // 3
            status = f"FAIL: {n} samples differ, first at x={i % w} y={i // w}"
        ok &= status == "OK"; done += 1
        print(f"{name:13s} {fid:6s} {w:4d}x{h:<4d} {status}")

def load(src, fid, pick=None):
    out = os.path.join(tmp, os.path.basename(src) + fid + str(pick) + ".rgb")
    r = subprocess.run([sc4, "load", src, out, fid] + ([str(pick)] if pick is not None else []), capture_output=True, text=True)
    return (open(out, "rb").read() if r.returncode == 0 else None), r.stdout.strip() or r.stderr.strip()
def crop(rgb, w, cw, ch): return b"".join(rgb[y * w * 3:(y * w + cw) * 3] for y in range(ch))
def same(label, a, b):
    global ok, done
    done += 1
    good = a[0] is not None and a[0] == b
    ok &= good
    print(f"{label:58s} {'OK' if good else 'FAIL: ' + a[1][:60]}")
A, M = os.path.join(fix, "apple"), os.path.join(fix, "a2more")
if os.path.isdir(M):
    hgr, dhr, dhrbw = (load(os.path.join(A, n), f)[0] for n, f in (("HGR.PIC", "hgr"), ("DHR.PIC", "dhr"), ("DHRBW.PIC", "dhrbw")))
    same("LZ4FH HiRes: as the plain file", load(os.path.join(M, "LZ.HGR"), "hgr"), hgr)
    same("LZ4FH from 8184 bytes: as the plain file", load(os.path.join(M, "LZ2.HGR"), "hgr"), hgr)
    same("PackBytes HiRes: as the plain file", load(os.path.join(fix, "newfmt", "HGR.PK"), "hgr"), hgr)
    same("PackBytes Double HiRes: as the plain file", load(os.path.join(fix, "newfmt", "DHR.PK"), "dhr"), dhr)
    same("PAIR.BIN with PAIR.AUX: Double HiRes", load(os.path.join(M, "PAIR.BIN"), "dhr"), dhr)
    same("PAIR.AUX opened instead", load(os.path.join(M, "PAIR.AUX"), "dhr"), dhr)
    same("8184-byte halves, lower-case names", load(os.path.join(M, "pair2.aux"), "dhr"), dhr)
    same("Full-screen piece (FULL.DHR)", load(os.path.join(M, "FULL.DHR"), "dhr"), dhr)
    ref = load(os.path.join(M, "PIECEREF"), "dhr")[0]
    same("Piece 40 bytes x 100 rows: 140 x 100 of the screen", load(os.path.join(M, "PIECE.DHR"), "dhr"), crop(ref, 280, 140, 100))
    ref = load(os.path.join(M, "MASKREF"), "dhrbw")[0]
    same("Mask piece 20 x 50: 140 x 50 black & white", load(os.path.join(M, "MASK.DHM"), "dhrbw"), crop(ref, 560, 140, 50))
    for n in ("TALL", "WIDE", "M3200"):
        same(f"Apple Preferred {n}: as the file holds it", load(os.path.join(M, n + ".APF"), "shr"), open(os.path.join(M, n + ".EXP"), "rb").read())
W = os.path.join(fix, "woa", "TEST.WOA")
if os.path.exists(W):
    sys.path.insert(0, os.path.join(os.path.dirname(fix.rstrip("/")), "..", "test"))
    d = open(W, "rb").read()
    lengths = [int.from_bytes(d[16 + 16 * k + 8:16 + 16 * k + 10], "little") for k in range(4)]
    offs = [512 + sum(lengths[:k]) for k in range(4)]
    for k in (1, 2):
        chunk = d[offs[k]:offs[k] + lengths[k]]
        bits, strip, y, down, i = [0] * (270 * 360), 0, 0, True, 10
        def put(c):
            global strip, y, down
            if strip >= 39: return
            for b in range(7):
                if c >> b & 1 and 7 * strip + b < 270: bits[y * 270 + 7 * strip + b] = 1
            if down:
                if y == 359: strip += 1; down = False
                else: y += 1
            else:
                if y == 0: strip += 1; down = True
                else: y -= 1
        while i < len(chunk):
            c = chunk[i]; i += 1
            if c < 0x80: put(c); continue
            n, count = ((c >> 4) & 7) + 1, c & 15
            if count >= 8: count = (count & 7) << 8 | chunk[i]; i += 1
            pat = chunk[i:i + n]; i += n
            for _ in range(count + 1):
                for p in pat: put(p & 0x7F)
        want = bytes(v for b in bits for v in ((255, 255, 255) if b else (0, 0, 0)))
        same(f"Works of Art page {k}: as decoded from the notes", load(W, "woa", k - 1), want)

print("all the same" if ok else "PROBLEMS", f"({done} pictures)")
sys.exit(0 if ok else 1)
