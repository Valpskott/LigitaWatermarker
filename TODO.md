# TODO - Ligita Watermarker

---

## [CHORE] Remember checkbox state across runs — FIXED ✓

**File:** `run_me.ps1`
Saved `doNumbers` and `doWatermark` bools into `.state.json`. Restored at startup via fallback-safe read. Persisted on Browse OK (alongside `lastFolder`).

---

## [FEATURE] In-window terminal for processing output — FIXED ✓

**File:** `run_me.ps1`

Added a dark-themed read-only RichTextBox (`#1e1e1e` bg, white/Consolas 9pt) between the settings row and the Cancel/Process buttons. Form height increased from 430 → 540 px.
- Created `Log-Output` helper accepting message + severity level (`info`=white, `warn`=yellow, `error`=red), auto-scrolls to end
- Replaced all `Write-Host` calls with `Log-Output`
- Replaced `Write-Warning` in the catch block with `Log-Output <msg> warn`

---

## [FEATURE] Keep UI open after processing (re-select & re-process) / Rename Run → Process — FIXED ✓

**File:** `run_me.ps1`

Extracted everything after `$form.ShowDialog()` into `function Process-Folder {}`. The Process button now calls this via an `Add_Click` handler instead of closing the dialog on `DialogResult::OK`.
- On entry: disables all interactive controls (Browse, Process, checkboxes, text boxes), clears the terminal
- On exit (`finally`): re-enables all controls; terminal output stays visible for inspection
- Cancel / X still closes immediately via `DialogResult::Cancel`
- Button renamed from "Run" to "Process"

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
