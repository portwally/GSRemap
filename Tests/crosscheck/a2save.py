# Checks GS Remap's Apple II save formats against MegaconvertGS's model of them (its
# test/check_a2save.py model(), which MegaconvertGS's own saves match byte for byte).
#   python3 Tests/crosscheck/a2save.py [MegaconvertGS folder]
import os, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
mg = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Documents/MegaconvertGS")
src = open(os.path.join(mg, "test", "check_a2save.py")).read()
ns = {"__file__": os.path.join(mg, "test", "check_a2save.py")}
saved, sys.argv = sys.argv, ["x"]
exec(compile(src[:src.index("\nok = True")], "check_a2save", "exec"), ns)
sys.argv = saved
model, unpackbytes = ns["model"], ns["unpackbytes"]
fix = os.path.join(mg, "build", "fixtures")
sc4 = os.path.join(root, ".build", "release", "sc4")
tmp = tempfile.mkdtemp()
PICTURES = [("S320.c1", "c1"), ("S640.c1", "c1"), ("apple/HGR.PIC", "hgr"), ("apple/DHR.PIC", "dhr"),
            ("apple/DHRBW.PIC", "dhrbw"), ("apple/HGRBW.PIC", "hgrbw"), ("newfmt/LORES", "lores"),
            ("newfmt/DLORES", "dlores"), ("apple/PSGS.GR", "psgs")]
FORMATS = ["hgr", "hgrbw", "dhr", "dhrbw", "lores", "dlores", "hgrp", "hgrbwp", "dhrp", "dhrbwp"]
OPTIONS = [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1)]
ok, n = True, 0
for path, fid in PICTURES:
    f = os.path.join(fix, path)
    out = os.path.join(tmp, "pic.rgb")
    r = subprocess.run([sc4, "load", f, out, fid], capture_output=True, text=True)
    if r.returncode: print(path, "FAIL:", r.stderr.strip()); ok = False; continue
    w, h = map(int, r.stdout.split()[1].split("x"))
    rgb = open(out, "rb").read()
    rows = [[((rgb[(y * w + x) * 3] // 17) << 8) | ((rgb[(y * w + x) * 3 + 1] // 17) << 4) | (rgb[(y * w + x) * 3 + 2] // 17)
             for x in range(w)] for y in range(h)]
    for fmt in FORMATS:
        for d, fit in (OPTIONS if not fmt.endswith("p") else [(0, 0)]):
            o = os.path.join(tmp, "out")
            r = subprocess.run([sc4, "save", f, o, fid, fmt, str(d), str(fit)], capture_output=True, text=True)
            got = open(o, "rb").read() if r.returncode == 0 else None
            if got is not None and fmt.endswith("p"): got = unpackbytes(got)
            want = model(rows, w, h, fmt[:-1] if fmt.endswith("p") else fmt, d, fit, w >= 560)
            good = got == want
            ok &= good; n += 1
            if not good:
                print(f"{path:18s} {fmt:7s} dither {d} fit {fit}: FAIL", (r.stderr.strip() or f"{sum(a != b for a, b in zip(got, want))} bytes differ") if got else r.stderr.strip())
print("all the same" if ok else "PROBLEMS", f"({n} saves)")
sys.exit(0 if ok else 1)
