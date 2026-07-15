# RUNBOOK - Ligita Watermarker

## Environment

- **OS:** Windows (no bash, no WSL)
- **Shell:** PowerShell 5.1
- **Working directory:** `X:\Code\Git\LigitaWatermarker`
- **Dependencies:** ImageMagick (`magick` CLI on PATH)

## Running Scripts

The agent has no native bash or WSL. Invokes `powershell.exe -ExecutionPolicy Bypass -File <script.ps1>` via underlying command wrapper.

**Inline `-Command "..."` does NOT work reliably.** When passing inline, outer shell strips `$`, breaking all PowerShell variables/expressions.

**Workaround:** Write script to temp file first, then run with `-File`.

## Codebase Overview

### Entry Point

**`run_me.ps1`** — Unified WinForms GUI tool:
- Folder picker dialog
- Checkboxes: "Add Numbers" (checked by default), "Add Watermark"
- Editable settings under a divider line + "Settings:" header: target width (px), font size (pt), watermark opacity (0..1)  
  - Defaults: 1280 px / 160 pt / 0.60 opacity
- **Cancel** and **Run** buttons anchored to bottom-right using `$form.ClientSize.Height` for placement
- Status label updated per-image with `Refresh()` calls

Output goes to sibling directory suffixed `_Numbered`, `_Watermarked`, or `_Processed`.

### Critical WinForms Bug (Discovered & Fixed)

After loading `System.Windows.Forms` into PS5's pipeline context, inline arithmetic inside `New-Object System.Drawing.Point(x,$varArith)` gets expanded into multiple constructor arguments instead of resolving first. Triggers "Cannot find overload with argument count 3" or `[object[]]::op_Subtraction()`.

**Fix:** All Point/Size constructors use helper functions (`MkPt`/`MkSz`) that call `[System.Drawing.Point/Size]::new()` directly, bypassing broken pipeline overload resolution.

### Processing Pipeline (per image)

1. `magick "$srcFile" -auto-orient "$tmpResize"` → temp resize file
2. **If numbering:** resize to target width, add rounded-rectangle background + number annotation via `-draw`/`-annotate` → tmpNumbers
3. **If watermarking:** composite shaded/watermark layers via SoftLight/HardLight compositing into final output  
4. **Intermediate buffer `$tmpSliced`** is used for SoftLight step to avoid read/write collision (IMv7 writes output to the same path as a source file would corrupt the operation)

Every iteration has its own `try / catch / finally`: bad images skip with warning, temps cleaned in `finally`.

### Form Layout

Client size 520 × 430. The fixed window border and title bar are *not* included, so all coordinates are pure content-area pixels:

| Control | X | Y (calculated) | W/H | Notes |
|---------|---|----------------|-----|-------|
| Folder label | 12 | 12 | 280×20 | Path preview |
| Browse button | 290 | `layoutY-24` | 130×24 | Aligned with folder label |
| "Options:" label | 12 | +8 gap | 80×20 | Section header |
| **Add Numbers** checkbox | 22 | calc | default | Checked by default |
| **Add Watermark** checkbox | 22 | calc | default | Unchecked by default |
| *---* | --- | +20 gap | --- | Blank spacer before divider |
| Divider line | 12 | calc | 460×1 | Flat gray hairline (`BorderStyle::None`, `LightGray` backcolor) |
| "Settings:" label | 12 | +8 gap | 80×20 | Section header matching Options: |
| **Target width** text box | 167 | calc | 70 wide | Row built via helper function |
| **Font size** text box | 167 | calc | 60 wide |  |
| **Opacity** text box | 167 | calc | 60 wide |  |
| Status label | 12 | +8 gap | 400×20 | Per-image progress feedback |
| *---* | --- | +5 gap | --- | Blank spacer before buttons |
| Cancel button | 215 | `clientH-50` | 90×30 | Anchored to form bottom |
| Run button | 310 | `clientH-50` | 110×30 | Anchored to form bottom |

## Known Quirks

- **PowerShell + ImageMagick argument quoting:** IMv7 dropped `magick convert`; use bare `magick` everywhere.
- **Numeric settings parsed with TryParse and clamped.** Opacity is forced into `[0,1]`, width/font-size reject non-positive values (fallback to default).
- **No StrictMode** in `run_me.ps1`. Some test scripts used it and hit string expansion bugs (`${prop}.Method()` under StrictMode looks up variable names).
- The watermark assets are resolved relative to the script's own directory at `Resolve-ScriptRoot` + `add_watermark_to_pics\angled_watermark\`. These two PNGs are checked at pre-flight:
  - `watermark-shaded.png` — SoftLight layer
  - `watermark-outline.png` — HardLight layer with opacity applied to alpha channel
