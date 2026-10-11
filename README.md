# GS Remap

A macOS port of SuperConvert 4.0 (Apple IIgs, Seven Hills Software) built by reverse
engineering the original program. The conversion engine is reimplemented in Swift from
the disassembly and the manual; the window mimics the IIgs desktop.

## Screenshots

<img src="docs/icon-preview.png" width="128" alt="GS Remap icon">

The desktop: Load formats, Save formats and the Image window.

![The GS Remap desktop](docs/screenshots/desktop.png)

The Remap dialog: graphic mode, palette, rendering algorithm and scaling. The diagram shows
the resulting picture against a grid of screens; the curve is the 64K size limit.

![Remap dialog](docs/screenshots/remap.png)

A picture too large for the limit: the thin outline is the size asked for, the thick one is
what you get.

![Remap dialog with a clipped picture](docs/screenshots/remap-clipped.png)

A picture remapped to 640 x 200 dither mode with the default palette.

![640 dither mode result](docs/screenshots/640-dither.png)

The True color menu with its filters.

![True color menu](docs/screenshots/filters-menu.png)

A monochrome image made with error diffusion.

![Monochrome image](docs/screenshots/monochrome.png)

## Layout

- `Sources/SCCore` — conversion engine (no UI): image types, palette calculator,
  pattern dither, error diffusion, SHR and Apple II file formats
- `Sources/sc4` — command-line front end, handy for batch work and testing
- `App` — the SwiftUI app
- `Tests` — unit tests
- `docs/RE-NOTES.md` — what was learned from the original code

## Build

To build the app in Xcode, open `GSRemap.xcodeproj` (not the folder or `Package.swift`,
which only give you the engine and the command-line tool) and run the GSRemap scheme.

From the command line:

```bash
swift test
xcodegen generate
xcodebuild -project GSRemap.xcodeproj -scheme GSRemap -derivedDataPath .build/xcode build
```

## Status

Working: Remap (320, 640, 640 dither, multipalette; default, greyscale, calculated,
stored, current and "Get other" palettes; closest match, pattern dither, error
diffusion; scaling and clipping), Quick remap, mirror/flip/rotate.

True colour filters: histogram equalization, median, sigma, emboss, blur, sharpen, solarize,
find edges, increase and decrease contrast.

Monochrome images: conversion from screen and true colour images (error diffusion, pattern
dither, halftone, 50% threshold; 1X, 2X or 4X size), conversion back to either, negative, info.

Load, Apple II: HiRes and Double HiRes (colour or black & white), Print Shop graphics,
ThunderScan raw scans, TDM 40- and 80-column text screens.

Load, Apple IIgs: SHR ($C1, $C0/0, $C0/1, $C0/2 Apple Preferred), DreamGrafix (256 and
3200 colour), Paintworks Gold 640 mode files, Print Shop IIgs graphics and GRAPHIC.CGT
libraries, Finder icon files, AST and ComputerEyes digitizer data, 3200 colour pictures
(uncompressed, the $C0/$3200 packed form, and .3201 files).

Load, Atari ST: Degas, Degas Elite, Neochrome, Tiny, Spectrum 512 (.SPU and .SPC).

Load, Amiga: IFF ILBM, including Extra HalfBrite, HAM and 24-bit.

Load, Commodore 64: Doodle, Koala, Print Shop screens.

Load, Macintosh: MacPaint (640 mode greys or 320 mode black & white), ScreenMaker.

Load, IBM PC: BMP (via macOS), PC Paintbrush PCX, GEM / Ventura IMG, DeluxePaint LBM,
FliAway frame files.

Load, Unix: Sun Rasterfile, SGI Iris, Portable Pixelmap (PBM, PGM, PPM; text and binary).

Load, computer-independent: JPEG, PNG, GIF, TIFF via macOS; CompuServe RLE, IPI
(.R + .G + .B), QuickRayTracer raw files.

Save: $C0/0, $C0/1, $C0/2, $C1, Finder icon files (new or added to), rIcon resources (new
resource file or added to one), hex data, GIF, PNG, TIFF. IIgs files get a `#C00002`-style
suffix so tools such as CiderPress and cadius set the ProDOS file type.

Menus: every item of the original is present. Working: help and menu item help (with the
port's own help text), multiple-file loading with Load next, exchange load/save paths,
printing (normal, enhanced, alignment page), Examine file, paste, the half-size, X4 and
true colour views, use as desktop background, the font list and a system report.

Left dimmed, with the reason in Menu item help: Undo and Clear (desk accessories only on
the IIgs), View interlaced on VOC, Oscilloscope Art, Font key chart, Print banner.

Not ported: the desktop background INIT save format, Works of Art and New Print Shop files,
and the Babelfish translators.

## License

The source code is released under the MIT License (see `LICENSE`).

The fonts in `App/Fonts` are not covered by it. They are by Kreative Software and remain
under the Kreative Software Relay Fonts Free Use License (`App/Fonts/ShastonLicense.txt`),
which among other things does not allow selling copies of the fonts.

SuperConvert is a trademark of Seven Hills Software Corporation. GS Remap is an independent
project and is not affiliated with or endorsed by its authors.
