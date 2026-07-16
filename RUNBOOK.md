# RUNBOOK - Ligita Watermarker

## Environment

- **OS:** Windows (no bash, no WSL)
- **Shell:** PowerShell 5.1
- **Working directory:** `X:\Code\Git\LigitaWatermarker`
- **Dependencies:** ImageMagick (`magick` CLI on PATH)

## Running Scripts

The agent has no native bash or WSL. Invokes `powershell.exe -ExecutionPolicy Bypass -File <script.ps1>` via underlying command wrapper.

**Inline `-Command "..."` does NOT work reliably.** Outer shell strips `$`, breaking all PS variables/expressions.

**Workaround:** Write script to temp file first, run with `-File`.

---

## Codebase

### Entry point: `run_me.ps1`

Unified WinForms GUI. Client size 520 × 430, FixedDialog title bar (no maximize button).

**Flow:**
1. **Browse** opens `FolderBrowserDialog`, defaulting to the path remembered in `.state.json`. After OK that chosen path is persisted for next launch.
2. **Options** — Add Numbers (checked) / Add Watermark (unchecked)
3. **Settings** under a gray hairline divider: target width (px), font size (pt), opacity (0..1). All validate/clamp on Run.
4. **Cancel / Run** buttons anchored 50 px from the bottom.
5. Status label refreshed per image during processing.

### Output behaviour

All processed images land inside a child folder named `"Processed"` beneath the selected path:

```
user selects: Z:\pics\2024-trip       →   output: Z:\pics\2024-trip\Processed\
if Processed already exists:           →   appends "+N"  (Processed+2, Processed+3, ...)
```

No `Remove-Item -Recurse` — runs never overwrite each other and originals are never touched.

### State file

`.state.json` lives next to the script, auto-created on first Browse OK:

```json
{ "lastFolder": "Z:\\pics" }
```

If the saved directory is deleted or corrupted JSON read fails → graceful fallback to Desktop.

---

### Critical WinForms bug (PS 5.1)

After `System.Windows.Forms` loads, inline arithmetic inside `New-Object System.Drawing.Point(x,$var+N)` triggers pipeline expansion that breaks overload resolution. 

**Fix:** helpers `MkPt()` & `MkSz()` call `[type]::new()` directly instead of using the broken pipeline evaluator.

---

### Processing pipeline (per image)

1. `magick "$srcFile" -auto-orient "$tmpResize"`
2. **If numbering** → resize + rounded rect + annotation ➜ `$tmpNumbers`  
3. **If watermarking** → SoftLight shaded layer into `$tmpSliced`, then HardLight outline ➜ final file  
4. Intermediate buffer `$tmpSliced` prevents IMv7 read/write collision

All temps use `"__tmp_*"` pattern, cleaned in a `finally` block every iteration — never touches source.

---

### Watermark assets location

```
<project root>/angled_watermark/watermark-shaded.png   (SoftLight layer)
<project root>/angled_watermark/watermark-outline.png  (HardLight layer, opacity applied to alpha at runtime)
```

---

## Task Tracking Workflow

**All requests must go into `TODO.md` first**:
- Write each task as a checkbox list item: `- [ ] Short description...`
- Break multi-step requests into numbered sub-tasks with clear file locations and old/new code snippets
- Check off items only after verification passes (`- [x] Task ... — FIXED ✓`)
- Never leave completed work undocumented; agent picking up next session reads `TODO.md`, not chat history

