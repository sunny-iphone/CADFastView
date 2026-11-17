# CADFastView (iOS Starter Project)

An offline, zero-tracking 2D CAD viewer for iPhone built with **SwiftUI**, featuring pan/zoom, layer management, distance/area/coordinate measurement, PDF export, and a C++ `libdxfrw` bridge for native `.dwg` and `.dxf` files.

## Quick Start (Runs Immediately)

1. Open `CADFastView.xcodeproj` in **Xcode 15+**.
2. Select an iPhone Simulator or your iPhone and press **Cmd + R**.
3. Tap **Load Sample** in the top bar (or **Open File** to pick any ASCII `.dxf` from the iOS Files app).

Out of the box, the app uses `FallbackDXFParser.swift` (pure Swift) so it compiles and runs immediately without external dependencies.

## Enabling Native `.dwg` + Binary `.dxf` via `libdxfrw` (GPL)

1. In Terminal, run the included fetch script from the project root:
   ```bash
   chmod +x scripts/fetch_libdxfrw.sh
   ./scripts/fetch_libdxfrw.sh
   ```
2. In Xcode, drag `Vendor/libdxfrw/src` into the `CADFastView` target (add `.cpp` and `.h` files to the target, excluding test/CLI `main` files if any).
3. In **Build Settings**:
   - Set **Header Search Paths** to include `$(SRCROOT)/Vendor/libdxfrw/src`.
   - Set **C++ Language Dialect** to `C++17`.
   - Under **Preprocessor Macros** (Apple Clang), add `USE_LIBDXFRW=1`.
   - Under **Other Swift Flags**, add `-DUSE_LIBDXFRW`.
4. Build and run—`CADParserBridge.mm` will now decode `.dwg` (R14–2015) and ASCII/binary `.dxf` files via `libdxfrw`.

> **Licensing Note:** `libdxfrw` is licensed under **GPL-2.0-or-later** (https://github.com/LibreCAD/libdxfrw). Keep this in mind if you plan to distribute outside personal/internal builds.
