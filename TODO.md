# TODO - Ligita Watermarker

---

## [CHORE] Remember checkbox state across runs — FIXED ✓

**File:** `run_me.ps1`
Saved `doNumbers` and `doWatermark` bools into `.state.json`. Restored at startup via fallback-safe read. Persisted on Browse OK (alongside `lastFolder`).

---

## [FEATURE] In-window terminal for processing output

Render a read-only RichTextBox between the settings section and the Cancel/Process buttons so all progress, warnings, and "Done." appear in the window itself rather than the outer shell.

**File:** `run_me.ps1`

### Implementation plan

1. **Add RichTextBox below settings row** (~line 157, after `$statusLbl / New-Row 5`). 490 px wide, ~85 px tall, dark background (`#1e1e1e`), white foreground, Consolas/9pt, read-only, vertical scrollbar.

2. **Create `Log-Output` helper** — appends a line to `$logBox`, auto-scrolls to end. Supports two severity levels:
   - `info` (default, white): per-file progress `[num/total] file.jpg`, "Done." summary
   - `warn` (yellow): skip/error lines

3. **Replace all logging in the processing loop**:
   - `Write-Host "[${num}/${total}] $($file.Name)"` → `Log-Output "[${num}/${total}] $($file.Name)"`
   - `Write-Warning "Skipping ..."` → `Log-Output "WARNING: Skipping ..." warn`
   - `Write-Host "Done. Output: $outDir"` → `Log-Output "Done. Output: $outDir"`

4. **Increase form height** from 430 to ~540 px to accommodate the terminal area.

---

## [FEATURE] Keep UI open after processing (re-select & re-process) / Rename Run → Process

After Processing a folder, the window should stay alive so the user can Browse another folder and Process again without relaunching. Also change "Run" button label to "Process".

**File:** `run_me.ps1`

### Implementation plan

1. **Extract everything after `$form.ShowDialog()` into `function Process-Folder {}`**. Includes: checkbox validation, numeric setting parse, pre-flight checks (magick PATH, watermark assets), output dir creation, per-file processing loop. Reads live values from form controls (`$chkNumbers.Checked`, `$txtWidth.Text`, etc.).

2. **Remove `DialogResult` off Run button**. Swap for a click handler:
   - On enter: disable Browse + Process buttons, clear terminal, call `Process-Folder`
   - On exit (finally): re-enable buttons, leave terminal output visible
   - Rename `$runBtn.Text = "&Process"` instead of `"&Run"`

3. **Cancel button**: keep its `DialogResult::Cancel` so it closes the form immediately (even mid-process; current iteration finishes gracefully via finally cleanup).

4. **Replace `$result = $form.ShowDialog(); if ($result -ne OK) exit`** with plain `$form.ShowDialog()` — the Cancel button or X close naturally; no upfront exit needed since processing now lives inside the click handler.

---

## [BUG] `Remove-Item $tmpNumbsed` — undefined variable causing runtime error — FIXED ✓

**File:** `run_me.ps1`
**Error at runtime:**
```
WARNING: Skipping '<file>.jpg': Cannot bind argument to parameter 'Path' because it is null.
```

There were **3 occurrences** of the bogus variable `$tmpNumbsed` at lines 294, 305 and 317. This name came from a broken chain of `sed -i` substitutions that stripped trailing characters off the real variable names. The script runs but every file throws this warning and gets skipped.

**Fix:** Mapped each broken `Remove-Item` to the correct temp variable:
- Line 294 (numbering ON): `$tmpNumbsed` → `$tmpResize` — clean up auto-oriented source consumed into numbering step
- Line 305 (no numbering + watermark): `$tmpNumbsed` → `$tmpResize` — same cleanup after resize to safe slot
- Line ~337 (numbers only): `$tmpNumbsed` → `$tmpNumbers` — numbered intermediate already copied to final dest

---

## Completed items (verified working)

### [BUG] If `Processed` subfolder already exists, delete instead of skip ahead — FIXED ✓

Location: `run_me.ps1` ~L237-240  
Was: while loop that auto-incremented to `Processed+2`, `+3` ... on collision  
Now: clobbers old Processed dir with safety guard (`$outDir.StartsWith($inDir)` → never nukes the parent/originals).

### [BUG] Numbered output filenames were `01-.jpg` instead of `01-originalname.jpg` — FIXED ✓

Location: `run_me.ps1` ~L259-264  
Root cause: `$file.BaseName` property access didn't resolve inside foreach + nested try/catch scoping rules in Powershell 5.1  
Fix: pull `$origBasename = $file.BaseName` out immediately after the assignment before inner blocks, then use that safe helper variable for concatenation instead of double-quote interpolation. Mirrors old script which hoisted `$baseFile` above per-file work too.

## [BUG] Watermarked images too bright — FIXED ✓

**File:** `run_me.ps1` ~L267-271
**Root cause:** The old watermark code used single-pipeline `magick convert` invocations that kept all intermediate images in memory during compositing. The new unified script uses separate `magick` commands — each writing an intermediate to disk, then the next command reading it back from disk. All photo intermediates (`__tmp_resize.jpg`, `__tmp_numbers.jpg`, `__tmp_sliced.jpg`) were JPEG, so every write/read cycle introduced lossy compression artifacts. SoftLight/HardLight compositing uses per-pixel luminance formulas that are extremely sensitive to even tiny pixel-level noise — the accumulated artifacts across multiple JPEG round-trips compounded into visible brightness/banding increase.
**Fix:** Changed all photo intermediates from `.jpg` to `.png` (lossless). Only the final output `$dstFile` is still JPEG — one conversion, exactly matching old code behavior.
