# SuperConvert 4.0 — reverse-engineering notes

Working notes from disassembling `SuperConvert` (S16, aux $DB07) from the
`Super Convert 4.2mg` disk image. Addresses are `segment/offset` using the
fictional layout "segment N loads at $NN0000".

## Tools (in the session scratchpad, `tools/`)

- `omfsegs.py` — list OMF segments
- `rfork.py` — dump the IIgs resource fork, one file per resource
- `dis.py` — OMF loader + relocator + 65816 linear disassembler
- `names.py` — pull GSBug debug names (`BRL` / `$7771` / pstring) → 238 symbols

## File layout

| Seg | Name | Notes |
|---|---|---|
| 2 | (main) | ORCA-compiled helpers: palette calculation, pattern tables, colour distance |
| 4 | INITIALIZE | startup |
| 5 | MAINE | main program, load-format tables (`LFxxx` help labels sit next to format names) |
| 6 | FRED | help viewer, monochrome image code, Mac/RLE/WOA loaders, PNG/JPEG/Babelfish glue |
| 7 | SPAM | 63 KB, 19 relocs — mostly hand-written loaders/tables |
| 8 | LONGCODE | Remap dialog + engine ($9F28–$DB37), multi-file loading, desktop INIT, icons |
| 9 | OSAYCANYOU | "Get other" palettes, prefs, SGI/Ventura loaders |
| 10 | SUPERFX | true-colour effects |
| 11–21 | png, djpeg*, INFLATE, jmisc, png* | libpng / IJG JPEG / zlib (replaced by macOS frameworks) |
| 23–26 | DYNAMIFF, DYNAMINFO, DYNAMDESK, DYNAMTIFF | dynamic segments |

## Image model

Three image types: **screen** (SHR), **true colour**, **monochrome**.

- True colour = one 16-bit word per pixel, `$0RGB` (4 bits per channel, 4096
  colours). Bit 15 set = "no pixel" (transparent / outside image).
  Globals: handle `08/0F21`, width `08/0F3F`, height `08/0F41`.
- Remap globals: graphic mode `08/0F31` (0=320, 1=640, 2=640 dither, 3=multipalette),
  palette choice `08/0F33`, algorithm `08/0F35` (0=closest, 1=pattern, 2=error diffusion).

## Palette prototypes (`08/9790`, built by SeTheProto `08/B517`)

Word 0 = entry count (16 for 320, 4 for 640, 8 for 640 dither); bit 15 set
means a multipalette option code instead. Each entry is `$0RGB` plus flags:

- `$8000` — slot reserved, never used by the remap (keeps the colour shown)
- `$4000` — slot to be filled by the palette calculator
- neither — fixed colour, used as is

"Get other" lists (`09/0000`…): pstring name, count word, entries.

320 mode:
- Black & white only: `0000 8777 8841 872C 800F 8080 8F70 8D00 8FA9 8FF0 80E0 84DF 8DAF 878F 8CCC 0FFF`
- Apple II LoRes/Double HiRes: `0000 0D03 0852 0F60 0070 0555 00D0 0FF0 0009 0D0D 0AAA 0F98 022F 06AF 00F9 0FFF`
- Apple II HiRes: `0000 8D03 8852 0F60 8070 8555 00D0 8FF0 8009 0D0D 8AAA 8F98 022F 86AF 80F9 0FFF`
- Calculate 14, leave 2: `0000 4777 4841 472C 400F 4080 4F70 4D00 4FA9 4FF0 40E0 44DF 4DAF 878F 8CCC 0FFF`
- Calculate 9, leave 7: `0000 4777 4841 472C 400F 4080 4F70 4D00 8FA9 8FF0 80E0 84DF 8DAF 878F 8CCC 0FFF`
- Quick Remap palette: `0000 000F 00F0 00FF 0F00 0F0F 0FF0 8FFF 8000 0222 0444 0666 0999 0BBB 0DDD 0FFF`

640 mode (4): B&W `0000 8F00 80F0 0FFF`; CMY `0000 00FF 0F0F 0FF0`;
RGB+white `0F00 00F0 000F 0FFF`; 3 greys + spare `0000 8F00 0AAA 0FFF`.

640 dither (8): B&W `0000 8F00 80F0 0FFF 0000 800F 8FF0 0FFF`;
backwards default `0000 000F 0FF0 0FFF 0000 0F00 00F0 0FFF`;
greys + spare `0000 8F00 0777 0FFF 0000 800F 0CCC 0FFF`.

Multipalette options: codes `$8001` max 8 palettes, `$8002` optimised
selection, `$8003` zone division, `$8004` zone division max 8.

Standard 320 palette: `000 777 841 72C 00F 080 F70 D00 FA9 FF0 0E0 4DF DAF 78F CCC FFF`.

## Colour maths (segment 2)

- Distance `02/6CFA`: `a=3·dR, b=4·dG, c=2·dB` (4-bit channels);
  `d = |a| + |b| + |c| + (|a+b+c| >> 2)`.
- Brightness `02/6F9C`: `5·R + 8·G + 3·B`.
- Prototype check `02/6BA8`: returns 0 = multipalette, 1 = needs calculation,
  2 = all usable entries grey (R=G=B) → sets grey flag `02/7E2D`, which is what
  enables Error diffusion. 8-entry prototypes are checked as two halves.

## Calculated palette (`02/6FF4`)

Input: 4096-entry histogram of the scaled image (word counts).

1. Fixed entries: zero their histogram count (they are already covered).
2. If the image has no more distinct colours than free slots: use them directly.
3. Otherwise popularity with neighbourhood suppression:
   - find max count `M`; add a bias to every non-zero count:
     `count += M/8 + dist(colour, $777) · M / 9` (saturating at $FFFF) — favours
     colours far from mid-grey.
   - for every fixed colour, then each chosen colour: `Reduce(hist, colour, 50)`
     (`02/6E4B`): every colour within distance 50 gets
     `count = max(1, count · dist / 50)`.
   - repeat: pick max-count colour, zero it, reduce around it — until slots are full
     or the histogram is empty.
4. Chosen colours that already match a `$4000` slot's default keep that slot.
   Remaining slots are filled in order, each taking the darkest remaining colour
   (brightness-sorted, so the palette ascends from black to white).
5. 640 dither: unfilled slots in the second half copy from the first half.

## Pattern tables (`02/7A19`, `02/7842`, `02/74C8`, `02/7601`)

Candidate patterns:

| Mode | Algorithm | Candidates |
|---|---|---|
| 16 colours | closest | 16 × 1 pixel |
| 16 colours | pattern | 256 × 2 pixels (`i & 15`, `i >> 4`) |
| 640 (4) | closest | 4 × 1 pixel |
| 640 (4) | pattern | 256 × 4 pixels (`i&3`, `i>>2&3`, `i>>4&3`, `i>>6`) |
| 640 dither (8) | closest | 16 × 2 pixels (`(i&3)+4`, `i>>2`) |
| 640 dither (8) | pattern | 256 × 4 pixels, odd columns use entries 4–7 |

Per candidate (`7842`): average R, G, B of its pixels through intensity table
`02/8355`, rounded division; plus a spread penalty =
`Σ(3|r−R̄| + 4|g−Ḡ| + 2|b−B̄|) / n`. Any reserved (`$8000`) colour disables it.

Best candidate for a target (`74C8`): minimise
`3|R̄−r| + 4|Ḡ−g| + 2|B̄−b| + penalty/16`; scan from highest index down,
strict improvement only.

Two-row patterns (`7601`): row 0 = best candidate for the target; row 1 = best
candidate for the error-compensated target `clamp(2·target − row0 average)`,
stored with its pixel pairs swapped so the rows checker.

Results are cached per colour: 256 entries when the image/palette is grey,
otherwise one entry per 12-bit colour present in the histogram.

## Quick Remap (`08/B762`)

Max 320×200 → 160-byte rows of 320-mode pixels using the Quick Remap palette.
Ordered 2×2 dither: thresholds `[5, 12, 14, 9]` (row 0: 5, 12; row 1: 14, 9);
each 4-bit channel ≥ threshold sets a bit; index = `R<<2 | G<<1 | B`.

## Rotate/flip (`08/B8AC`)

Option bits: 1 = mirror horizontally, 2 = flip vertically, 4 = transpose.

## Later findings

- **True colour pixel word** (decoded in `08/B484`): bit 15 set = 8-bit grey in the low
  byte. Otherwise 15-bit colour: bits 11–0 are the high nibbles `$RGB`, bits 14/13/12 are
  the extra low bit of R/G/B. Each 5-bit channel expands to 8 bits as `rrrrr rrr`.
- **Intensity table `02/8355`**: `0 1 5 10 18 28 41 56 73 92 113 137 163 192 222 255`.
- **Scaling `08/B1C0` GetScaLine**: per output pixel, sums 8-bit channels over the source
  box and divides by the count (replicates when enlarging). Also produces a grey line:
  `(5R + 8G + 3B) >> 4`.
- **Renderer `08/BDCE`**: colour index = top nibbles of the averaged R, G, B; pattern
  bytes come from two 4097-byte tables (even rows `08/7788`, odd rows `08/8789`); each
  output pixel takes its own slot of the byte (mask `$F0/$0F` in 320, `$C0…$03` in 640).
- **Grey palettes**: when every usable palette entry is grey the remap goes through a
  256-entry table indexed by the grey line instead (`08/BED3`; `08/BFBD` with error
  diffusion, which uses single-colour candidates).
- **Two-row assembly `02/7707`**: with first/second candidate `p1`/`p2`, the larger index
  is stored as is in one row and the smaller, nibble-swapped, in the other.
- **Rounded divide `02/77F7`**: truncating, but a non-zero sum never becomes 0.

## Not ported one for one

- Multipalette palette allocation (`08/C397` …): the Mac port seeds even zones and lets
  lines migrate to the best palette instead.
- Error diffusion kernels in `08/BFBD` were not traced; the help text says standard
  Floyd-Steinberg with serpentine scan, which is what the port does.
- `08/AC49` CalcClips: the port applies the same 64K rule from the documentation.

## Load formats (table at 05/30C6…, 32-byte records)

Record: name pointer, flags (`$0100` screen, `$0200` true colour, `$0400` monochrome),
two accepted file types, size range, auxtype range, loader address, help label pointer.

| Format | Loader | Layout |
|---|---|---|
| Print Shop B&W | 05/8767 | 572 bytes = 52 rows x 11 bytes, high bit first, 1 = ink |
| Print Shop IIgs | 05/87B4 | three 572-byte planes: yellow, magenta, cyan. Index `Y<<2\|M<<1\|C` → default-palette colours `F 4 7 3 9 A 6 0` (table 05/88E9) |
| GRAPHIC.CGT0-7 | 05/8AC8 | several 1716-byte colour graphics, names after them |
| ThunderScan | 05/6154 | 256-byte header: width word at $0F, height-1 word at $1E, bit 0 of $0A = 640-shaped pixels; rows of 4-bit greys |
| DreamGrafix | 05/6EF6, 05/6DB9 | LZW (07/0000): 9–12 bit codes, low bit first, clear $100, end $101. Unpacks to a $C1 screen (32768) or 32000 pixels + 200 colour tables |
| Paintworks Gold 640 | 05/6C04 | reads the file normally but forces 640 mode, 640 pixels per line and SCB $80 |
| Finder icons | 05/7394 | file-type note $CA layout; records start at offset 26, big icon at +86 |
| AST | 05/5974 | 96000 bytes: R, G, B planes of 200 x 160 bytes, two 4-bit samples per byte |
| ComputerEyes GS | 05/6206 | three planes (R, G, B) of 6-bit samples, stored column by column (x·200 + y) |
| 3200 uncompressed | 05/5D97 | 32000 pixels + 200 tables of 16 words, tables stored last colour first (05/5E25 uses index 15 − pixel) |
| 3200 compressed ($C0/$3200) | 05/5DD0 | 7-byte header, word at +5 = packed size of the tables; two streams packed with 05/5EBE: top 3 bits = op (0/1 byte run, 2–5 runs of 2–5 byte units, 6/7 literal), low 5 bits = count, ops 1 and 7 take a second count byte |
| TDM text | 05/771B, 05/7734 | raw text page; the original read the character ROM, the port uses Print Char 21 glyphs |
| Works of Art | 06/AEBA | not ported: chunk directory, page list, column-wise run-length codec, monochrome result |
| New Print Shop | — | the table's loader field is zero |

Double HiRes colour number: the first dot of each 4-dot group is the high bit.

| RLE | 06/ADD4 | CompuServe: scan for ESC "G", then "H" = 256 x 192, else 128 x 96; each character minus 32 is a run, colours alternate from black |
| IPI | 05/5A5A (256), 05/5A5F (512) | three files .R .G .B of raw 8-bit samples, row by row |
| QRT | 05/5C9B | width word, height word; then per line: line number word, row of R, row of G, row of B |
| FliAway frame | 05/6060 | 256 true-colour words, packed-size word (0 = raw), 64000 pixel bytes (PackBytes) |

## Save formats

- **Hex data**: the three default strings sit at 09/36B9 ("'", after), 09/36D0 (" ", between)
  and 09/36E7 (" dc h'", before); the sample line template is `*0 01 *1 23 … *2`.
- **Icons**: Finder icon records and rIcon resources share one layout: type word ($8000 =
  colour), image size in bytes, height, width in 4-bit pixels, image, mask.
- **Resource fork layout** (measured on the original's own fork): 140-byte header (version 0,
  offset to map = $8C, map size, 128-byte memo); map = 32-byte header, 10 free-list entries,
  4 spare bytes, 20-byte index entries, 2 spare bytes; resource data follows the map. The one
  used free-list entry is (end of file, $FFFFFFFF − end of file).
- **Desktop background INIT** (dynamic segment 25, DYNAMDESK): not ported. It writes a IIgs
  program built from a code template inside the original.

## True colour filters (segment 10, SUPERFX)

A shared driver (0A/0000) keeps three rows per channel and hands each filter the 3 x 3
neighbourhood as 5-bit values (R at dp $04–$14, G at $1A–$2A, B at $30–$40).

| Filter | Code | What it computes |
|---|---|---|
| Median | 0A/03BE | middle value of the nine |
| Sigma | 0A/0494 | average of neighbours within ±32 of the centre — on 5-bit values that is all of them |
| Emboss | 0A/059F | kernel `-1 -2 0 / -2 0 2 / 0 2 1`, plus mid grey, clamped |
| Blur | 0A/08B7 | kernel `1 2 1 / 2 w 2 / 1 2 1`, w = (100 − factor)/2 − 13, divided by w + 12 |
| Sharpen | 0A/0B14 | kernel `-1 -2 -1 / -2 w -2 / -1 -2 -1`, w = (100 − factor)/2 + 13, divided by w − 12 |
| Solarize | 0A/0D81 | values above 16 (of 31) become 31 − value |
| Find edges | 0A/0E7C | gain x (centre − mean of the four diagonal neighbours), gain = (100 − factor)/20 + 1.5 |
| Contrast | 0A/152D | converts to hue/saturation/value and bends the value along a sine curve (uses π = $3243F) |

Blur, sharpen and find edges take the "Factor" (0–99) from the dialog at 0A/06E5.
Histogram equalization lives elsewhere (08/E796) and was not traced; nor were the
monochrome rendering patterns (06/C52B onward).
