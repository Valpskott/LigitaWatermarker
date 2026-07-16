# Ligita Watermarker - Unified Tool

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ─── Config defaults ───────────────────────────────────────────────
$DEFAULT_TARGET_WIDTH = 1280
$DEFAULT_FONT_SIZE    = 160
$DEFAULT_OPACITY      = 0.60
$FILE_TYPES           = "png", "jpg", "bmp"

# ─── Helpers ───────────────────────────────────────────────────────

$scriptRoot      = Split-Path -Parent $PSCommandPath

function Get-ImageDimensions($filePath) {
    $output = & magick identify $filePath
    if ($output -match '(\d+)x(\d+)') {
        return @{ Width = $matches[1]; Height = $matches[2] }
    } else {
        throw "Failed to parse dimensions from: $output"
    }
}


# ─── Build Form ────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Ligita Watermarker"
$form.ClientSize     = [System.Drawing.Size]::new(520, 430)
$form.StartPosition  = $([System.Windows.Forms.FormStartPosition]::CenterScreen)
$form.FormBorderStyle = $([System.Windows.Forms.FormBorderStyle]::FixedDialog)
$form.MaximizeBox     = $false

[int]$layoutX      = 12
[int]$layoutCursorY = 12

# PS5 + WinForms bug: New-Object System.Drawing.Point(x, $varArithExp) breaks because
# overload resolution treats inline arithmetic as extra arguments after forms loaded.
# Use [System.Drawing.Point]::new() to bypass the pipeline expansion.
function MkPt { param([int]$x,[int]$y) [System.Drawing.Point]::new($x,$y) }
function MkSz { param([int]$w,[int]$h) [System.Drawing.Size]::new($w,$h) }

function New-Row { param([int]$h=24) $script:layoutCursorY = [int]$script:layoutCursorY + $h }

# ── Folder selection ────────────────────────────────────────────────
$folderLabel = New-Object System.Windows.Forms.Label
$folderLabel.Location = MkPt $layoutX $layoutCursorY
$folderLabel.Size     = MkSz 280 20
$folderLabel.Text     = "No folder selected"
$form.Controls.Add($folderLabel); New-Row

$browseBtn = New-Object System.Windows.Forms.Button
$browseBtn.Location = MkPt 290 ([int]$script:layoutCursorY - 24)
$browseBtn.Size     = MkSz 130 24
$browseBtn.Text     = "&Browse..."
$form.Controls.Add($browseBtn)

$selPath = ""

# ── Remember last folder via sidecar state file ───────────────────────
$stateFilePath = Join-Path $scriptRoot ".state.json"
$lastKnownFolder = ""
$lastDoNumbers   = $true    # checkbox defaults
$lastDoWatermark  = $false
if (Test-Path $stateFilePath) {
    try {
        $saved = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json
        if ($saved.lastFolder -and (Test-Path $saved.lastFolder -PathType Container)) {
            $lastKnownFolder = $saved.lastFolder
        }
        # Restore checkboxes only when a valid path exists (file is well-formed)
        if ($saved.doNumbers       -ne $null) { $lastDoNumbers   = [bool]$saved.doNumbers }
        if ($saved.doWatermark     -ne $null) { $lastDoWatermark = [bool]$saved.doWatermark }
    } catch { $lastKnownFolder = "" }
}

$browseBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description         = "Select folder with pictures"
    $dlg.ShowNewFolderButton = $false
    if ($script:lastKnownFolder -and (Test-Path $script:lastKnownFolder -PathType Container)) {
        $dlg.SelectedPath = $script:lastKnownFolder
    } else {
        $dlg.RootFolder = $([Environment+SpecialFolder]::Desktop)
    }
    if ($dlg.ShowDialog() -eq $([System.Windows.Forms.DialogResult]::OK)) {
        $script:selPath     = $dlg.SelectedPath
        $folderLabel.Text   = $selPath
        # persist selection + checkbox state for next run
        try {
            @{
                lastFolder  = $dlg.SelectedPath
                doNumbers   = $chkNumbers.Checked
                doWatermark = $chkWatermark.Checked
            } | ConvertTo-Json | Set-Content -Path $script:stateFilePath -Force
        } catch {}
    }
})

# ── Option checkboxes ───────────────────────────────────────────────
$layoutCursorY += 8
$optLbl = New-Object System.Windows.Forms.Label
$optLbl.Location = MkPt $layoutX $layoutCursorY
$optLbl.Size     = MkSz 80 20
$optLbl.Text     = "Options:"
$form.Controls.Add($optLbl); New-Row

$chkNumbers = New-Object System.Windows.Forms.CheckBox
$chkNumbers.Location = MkPt ([int]$script:layoutX + 10) $layoutCursorY
$chkNumbers.Text     = "&Add Numbers"
$chkNumbers.Checked   = $lastDoNumbers
$form.Controls.Add($chkNumbers); New-Row

$chkWatermark = New-Object System.Windows.Forms.CheckBox
$chkWatermark.Location = MkPt ([int]$script:layoutX + 10) $layoutCursorY
$chkWatermark.Text     = "&Add Watermark"
$chkWatermark.Checked   = $lastDoWatermark
$form.Controls.Add($chkWatermark); New-Row

# ── Settings section ────────────────────────────────────────────────
$layoutCursorY += 20
$sep = New-Object System.Windows.Forms.Label
$sep.Location    = MkPt $layoutX $layoutCursorY
$sep.Size        = MkSz 460 1
$sep.BackColor   = [System.Drawing.Color]::LightGray
$sep.BorderStyle = $([System.Windows.Forms.BorderStyle]::None)
$form.Controls.Add($sep); New-Row
$layoutCursorY += 8
$setLbl = New-Object System.Windows.Forms.Label
$setLbl.Location = MkPt $layoutX $layoutCursorY
$setLbl.Size     = MkSz 80 20
$setLbl.Text     = "Settings:"
$form.Controls.Add($setLbl); New-Row

function Add-SettingRow([string]$title, [object]$val, [int]$w=60) {
    $label = New-Object System.Windows.Forms.Label
    $label.Location = MkPt ([int]$script:layoutX + 10) $layoutCursorY
    $label.Size     = MkSz 140 20
    $label.Text     = $title
    $form.Controls.Add($label)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = MkPt ([int]$script:layoutX + 155) $layoutCursorY
    $tb.Width    = $w
    $tb.Text     = $val.ToString()
    $form.Controls.Add($tb)

    return $tb
}

$txtWidth   = Add-SettingRow "Target width (px):"        $DEFAULT_TARGET_WIDTH 70
New-Row
$txtFontSize = Add-SettingRow "Number font size (pt):"   $DEFAULT_FONT_SIZE    60
New-Row
$txtOpacity = Add-SettingRow "Watermark opacity (0..1):" $DEFAULT_OPACITY      60

# ── Status label ────────────────────────────────────────────────────
$layoutCursorY += 8
$statusLbl = New-Object System.Windows.Forms.Label
$statusLbl.Location = MkPt $layoutX $layoutCursorY
$statusLbl.Size     = MkSz 400 20
$statusLbl.Text     = ""
$form.Controls.Add($statusLbl); New-Row 5

# ── Buttons ─────────────────────────────────────────────────────────
$btnY = $form.ClientSize.Height - 50

$cancelBtn = New-Object System.Windows.Forms.Button
$cancelBtn.Location     = MkPt 215 $btnY
$cancelBtn.Size          = MkSz 90 30
$cancelBtn.Text         = "Cancel"
$cancelBtn.DialogResult = $([System.Windows.Forms.DialogResult]::Cancel)
$form.Controls.Add($cancelBtn)

$runBtn = New-Object System.Windows.Forms.Button
$runBtn.Location     = MkPt 310 $btnY
$runBtn.Size         = MkSz 110 30
$runBtn.Text         = "&Run"
$runBtn.DialogResult = $([System.Windows.Forms.DialogResult]::OK)
$form.Controls.Add($runBtn)

# ─── Show form and process ──────────────────────────────────────────
$result = $form.ShowDialog()
if ($result -ne $([System.Windows.Forms.DialogResult]::OK)) { exit }

$doNumbers   = $chkNumbers.Checked
$doWatermark = $chkWatermark.Checked

if (-not $doNumbers -and -not $doWatermark) {
    [System.Windows.Forms.MessageBox]::Show("Please select at least one option.", "Nothing to do")
    exit
}
if ([string]::IsNullOrWhiteSpace($selPath)) {
    [System.Windows.Forms.MessageBox]::Show("No folder selected. Please use Browse first.", "No folder")
    exit
}

# Parse numeric settings (fall back to defaults on bad input)
[int]$targetWidth = $DEFAULT_TARGET_WIDTH
if (-not ([int]::TryParse($txtWidth.Text, [ref]$targetWidth)) -or $targetWidth -le 0) {
    $targetWidth = $DEFAULT_TARGET_WIDTH
}

[int]$fontSize   = $DEFAULT_FONT_SIZE
if (-not ([int]::TryParse($txtFontSize.Text, [ref]$fontSize)) -or $fontSize -le 0) {
    $fontSize    = $DEFAULT_FONT_SIZE
}

[float]$opacity  = $DEFAULT_OPACITY
if (-not ([float]::TryParse($txtOpacity.Text, [ref]$opacity))) {
    $opacity      = $DEFAULT_OPACITY
}
# Clamp opacity to valid range
$opacity = [math]::Max(0.0, [math]::Min(1.0, $opacity))

# ── Pre-flight checks ──────────────────────────────────────────────

# Resolve watermark assets relative to script location (needed by validation)
if ($doWatermark) {
    $waterDir   = Join-Path $scriptRoot "angled_watermark"
    $wmShaded   = Join-Path $waterDir "watermark-shaded.png"
    $wmOutline  = Join-Path $waterDir "watermark-outline.png"
}

try {
    Get-Command magick -ErrorAction Stop | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show("magick (ImageMagick) not found on PATH.
Please install ImageMagick and ensure 'magick' is available.", "Missing dependency")
    exit
}

if ($doWatermark -and (-not (Test-Path $wmShaded) -or -not (Test-Path $wmOutline))) {
    [System.Windows.Forms.MessageBox]::Show(
        "Watermark assets not found.
Expected:
  $wmShaded
  $wmOutline",
        "Missing files"
    )
    exit
}

# ── Output directory ────────────────────────────────────────────────
$inDir  = $selPath
$outDir = Join-Path $inDir "Processed"

if ($outDir.StartsWith($inDir)) {
    if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
}
New-Item -ItemType Directory -Path $outDir | Out-Null

# ── Process files ───────────────────────────────────────────────────
$seq   = 1
$total = (Get-ChildItem $inDir -File | Where-Object {
    $FILE_TYPES -contains $_.Extension.TrimStart('.').ToLower()
}).Count

$digits = [math]::Max(2, "$total".Length)

foreach ($file in Get-ChildItem $inDir -File | Sort-Object Name) {
    $ext     = $file.Extension.TrimStart('.').ToLower()
    if ($FILE_TYPES -notcontains $ext) { continue }

    $srcFile  = $file.FullName
    # output filename: numbered -> 01-OriginalName.jpg | watermark-only -> OriginalName.ext unchanged
    $num = "{0:D$digits}" -f $seq
    $origBasename = $file.BaseName   # pull value out before inner scope
    if ($doNumbers) {
        $dstName = "${num}-${origBasename}.jpg"
    } else {
        $dstName = $file.Name
    }
    $dstFile  = Join-Path $outDir $dstName

    $tmpResize  = Join-Path $outDir "__tmp_resize.png"
    $tmpNumbers = Join-Path $outDir "__tmp_numbers.png"
    $tmpWm1     = Join-Path $outDir "__tmp_wm1.png"  # PNG preserves watermark alpha for SoftLight compose
    $tmpWm2     = Join-Path $outDir "__tmp_wm2.png"
    $tmpSliced  = Join-Path $outDir "__tmp_sliced.png"

    Write-Host " [${num}/${total}] $($file.Name)"
    $statusLbl.Text = "[${num}/${total}] $($file.Name)"
    $form.Refresh()

    try {
        magick "$srcFile" -auto-orient "$tmpResize"

        $dims   = Get-ImageDimensions $tmpResize
        $origW  = $dims.Width
        $origH  = $dims.Height
        $newH   = [math]::Round(($origH / $origW) * $targetWidth)
        $res    = "{0}x{1}" -f $targetWidth, $newH

        if ($doNumbers) {
            magick "$tmpResize" -resize $res `
                -gravity SouthEast `
                -fill "rgba(0,0,0,0.6)" `
                -draw "roundRectangle $($targetWidth-($fontSize*6/5)),$($newH-($fontSize*5/4)),$($targetWidth-10),$($newH-10),15,15" `
                -fill white -font Arial -pointsize $fontSize `
                -annotate +10+10 "${seq}." `
                "$tmpNumbers"
            Remove-Item $tmpResize
        }

        if ($doWatermark) {
            # When no numbering, resize source photo here to a safe slot.
            # Do NOT use $tmpWm1 for the resized photo — it will be
            # overwritten with the shaded watermark on the next line.
            # This mirrors the old single-invocation magick convert approach
            # where resize + composite happened in ONE command.
            if (-not $doNumbers) {
                magick "$tmpResize" -resize $res "$tmpSliced"
                Remove-Item $tmpResize
            }

            if ($origH -gt $origW) {
                $wmSize = "{0}x{0}" -f $newH
            } else {
                $wmSize = "{0}x{0}" -f $targetWidth
            }

            magick "$wmShaded"  -resize $wmSize "$tmpWm1"
            magick "$wmOutline" -resize $wmSize `
                -background none -alpha set -channel A -evaluate Multiply $opacity `
                "$tmpWm2"

            if ($doNumbers) {
                # Source photo is in $tmpNumbers (already resized + numbered)
                magick "$tmpNumbers" "$tmpWm1" -gravity center -compose SoftLight `
                    -composite "$tmpSliced"
                magick "$tmpSliced" "$tmpWm2" -gravity center -compose HardLight `
                    -composite "$dstFile"
            } else {
                # Source photo is in $tmpSliced (resized but not clobbered)
                magick "$tmpSliced" "$tmpWm1" -gravity center -compose SoftLight `
                    -composite "$tmpNumbers"
                magick "$tmpNumbers" "$tmpWm2" -gravity center -compose HardLight `
                    -composite "$dstFile"
            }

            Remove-Item $tmpWm1, $tmpWm2, $tmpSliced -ErrorAction SilentlyContinue
        } else {
            if ($doNumbers) {
                Copy-Item $tmpNumbers $dstFile
                Remove-Item $tmpNumbers
            }
        }
    } catch {
        Write-Warning "Skipping '$($file.Name)': $($_.Exception.Message)"
    } finally {
        Get-ChildItem $outDir -Filter "__tmp_*" | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $seq++
}

Write-Host "Done. Output: $outDir"
