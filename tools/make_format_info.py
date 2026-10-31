# Makes Sources/SCCore/FormatInfo.swift: the Info on format text of every load and save
# format, taken from MegaconvertGS's (its src/FormatInfo.s, read by its
# docs/manual/formats.py) and adapted where GS Remap works differently.
#   python3 tools/make_format_info.py [MegaconvertGS folder]
import os, re, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
mg = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Documents/MegaconvertGS")
sys.path.insert(0, os.path.join(mg, "docs", "manual"))
from formats import load_lists, info_texts
types, saves = load_lists()
fmt, sav = info_texts()
reg = open(os.path.join(root, "Sources", "SCCore", "FormatRegistry.swift")).read()
gload = [(a or c, (b or d).replace('\\"', '"')) for a, b, c, d in re.findall(
    r'(?:screen|trueColor|modern|screenOrMono)\("(\w+)", "((?:[^"\\]|\\.)*)"|LoadFormat\(id: "(\w+)", name: "((?:[^"\\]|\\.)*)"', reg)]
gsave = [(a or c, b or d) for a, b, c, d in re.findall(
    r'(?:raw|modernSave|appleII)\("(\w+)", "([^"]+)"|SaveFormat\(id: "(\w+)", name: "([^"]+)"', reg) if (a or c) != "id"]
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
mload = {norm(name): n for _, fs in types for name, n, _ in fs}
msave = {norm(name): n for name, n, _ in saves}
LOAD_BY_ID = {"fliaway": 43, "sgi": 45, "pnm": 46, "ipi": 48}
SAVE_BY_ID = {"iconadd": 6, "ricon": 7, "riconadd": 8}

THEN = "which the Remap dialog then turns into a screen image"
def adapt(t):
    t = t.replace("MegaconvertGS", "GS Remap")
    t = re.sub(r",? remapped to (fit a 320 mode screen|320 mode)( with a calculated palette)?\.", f", {THEN}.", t)
    t = t.replace("High resolution (640 x 400, black & white) becomes a true color picture, " + THEN,
                  "High resolution (640 x 400, black & white) becomes a monochrome image")
    t = re.sub(r" ?Open takes an? [^.]*\.", "", t)
    t = t.replace("; Open takes any 8002-byte file this way.", ".")
    t = t.replace(" (Open reads a CPC screen this way, unless a .PAL file beside it says another mode)",
                  " (a .PAL file beside it can say another mode)")
    t = t.replace("Also NAME.BIN with NAME.AUX; Open reads .A2FM files and .DHM masks so.",
                  "Also NAME.BIN with NAME.AUX, and bmp2dhr’s .DHM masks.")
    t = t.replace("Loaded as it is; an Apple Preferred picture larger than the screen or with 3200 colors as a true color one.",
                  "Loaded as it is, at its whole size; an Apple Preferred picture with 3200 colors keeps a color table for every line.")
    return t.strip()

MODERN = "Read by macOS, every kind it knows. It becomes a true color picture, " + THEN + "."
LOAD_OWN = {
    "bmp": "Windows or OS/2 bitmap (.BMP): the plain picture file of Windows PCs.\n" + MODERN,
    "jpeg": "JPEG (JFIF): the usual format for photographs (.JPG), compressed with some loss.\n" + MODERN,
    "gif": "GIF: CompuServe’s Graphics Interchange Format (87a and 89a), up to 256 colors.\n" + MODERN,
    "png": "PNG (Portable Network Graphics): the lossless picture format of today’s computers.\n" + MODERN,
    "tiff": "TIFF: the Tagged Image File Format of desktop publishing and scanners.\n" + MODERN,
    "any": "Anything macOS can open: any picture file macOS reads, such as HEIC, WebP or PDF.\n" + MODERN,
}
SQUARE = "\nWritten as it looks, with square pixels: lines twice and 320 mode pixels twice across (a full screen gives 640 x 400). Each pixel keeps the color it shows, whatever its palette."
SAVE_OWN = {
    "gif": "GIF: a GIF file for other computers, written by macOS." + SQUARE,
    "png": "PNG: a PNG file for today’s computers, written by macOS." + SQUARE,
    "tiff": "TIFF: a TIFF file for desktop publishing and other programs, written by macOS." + SQUARE,
    "bmp": "BMP: a Windows bitmap for today’s computers, written by macOS." + SQUARE,
}

def entries(pairs, own, by_id, table, texts):
    out = []
    for gid, name in pairs:
        if gid in own: text = own[gid]
        else:
            n = by_id.get(gid, table.get(norm(name)))
            text = adapt(texts[n]) if n is not None and texts.get(n) else None
        if text is None: sys.exit(f"no text for {gid} ({name})")
        out.append((gid, text))
    return out

def swift(entries):
    def lit(t): return t.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return "\n".join(f'        "{gid}": "{lit(t)}",' for gid, t in entries)

load_e = entries(gload, LOAD_OWN, LOAD_BY_ID, mload, fmt)
save_e = entries(gsave, SAVE_OWN, SAVE_BY_ID, msave, sav)
open(os.path.join(root, "Sources", "SCCore", "FormatInfo.swift"), "w").write(f"""// Made by tools/make_format_info.py from MegaconvertGS's Info on format texts; don't edit.

/// The Info on format text of each load and save format, by its id.
public enum FormatInfo {{
    public static let load: [String: String] = [
{swift(load_e)}
    ]

    public static let save: [String: String] = [
{swift(save_e)}
    ]
}}
""")
print(len(load_e), "load and", len(save_e), "save texts")
