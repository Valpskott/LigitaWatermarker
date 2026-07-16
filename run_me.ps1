# Ligita Watermarker - Unified Tool

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# --- Config defaults -----------------------------------------------
$DEFAULT_TARGET_WIDTH = 1280
$DEFAULT_FONT_SIZE    = 160
$DEFAULT_OPACITY      = 0.60
$FILE_TYPES           = "png", "jpg", "bmp"

# --- Helpers -------------------------------------------------------

$scriptRoot      = Split-Path -Parent $PSCommandPath

function Get-ImageDimensions($filePath) {
    $output = & magick identify $filePath
    if ($output -match '(\d+)x(\d+)') {
        return @{ Width = $matches[1]; Height = $matches[2] }
    } else {
        throw "Failed to parse dimensions from: $output"
    }
}

# --- Terminal logger -----------------------------------------------
function Log-Output {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [string]$Severity = "info"
    )
    switch ($Severity) {
        "warn"  { $color = [System.Drawing.Color]::Yellow }
        "error" { $color = [System.Drawing.Color]::Red }
        default { $color = [System.Drawing.Color]::White  }
    }
    if ($script:logBox) {
        $script:logBox.SelectionColor = $color
        $script:logBox.AppendText("$Message`r`n")
        $script:logBox.ScrollToCaret()
    }
}

# --- Build Form ----------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Ligita Watermarker"
$form.ClientSize     = [System.Drawing.Size]::new(520, 540)
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

# -- Folder selection ------------------------------------------------
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

# -- Remember last folder via sidecar state file -----------------------
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

# -- Option checkboxes -----------------------------------------------
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

# -- Settings section ------------------------------------------------
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
New-Row
$txtStartAt = Add-SettingRow "Start at:"               1                    60

# -- Input filters: block non-numeric keystrokes in number fields -----
$intFilter   = { param($s,$e) if ($e.KeyChar -ge '0' -and $e.KeyChar -le '9' -or [char]::IsControl($e.KeyChar)) { return } $e.Handled = $true }
$floatFilter = { param($s,$e) if (($e.KeyChar -ge '0' -and $e.KeyChar -le '9') -or $e.KeyChar -eq '.' -or [char]::IsControl($e.KeyChar)) { return } $e.Handled = $true }
$txtWidth.Add_KeyPress($intFilter)
$txtFontSize.Add_KeyPress($intFilter)
$txtOpacity.Add_KeyPress($floatFilter)
$txtStartAt.Add_KeyPress($intFilter)

# -- Terminal (RichTextBox) ------------------------------------------
$layoutCursorY += 4
$logLbl = New-Object System.Windows.Forms.Label
$logLbl.Location        = MkPt ([int]$script:layoutX + 10) $layoutCursorY
$logLbl.Size            = MkSz 80 20
$logLbl.Text             = "Output:"
$form.Controls.Add($logLbl); New-Row

$script:logBox = New-Object System.Windows.Forms.RichTextBox
$logPos = MkPt ([int]$script:layoutX + 10) $layoutCursorY
$script:logBox.Location      = $logPos
$script:logBox.Size          = MkSz 490 170
$script:logBox.BackColor     = [System.Drawing.Color]::FromArgb(30, 30, 30)
$script:logBox.ForeColor     = [System.Drawing.Color]::White
$script:logBox.Font          = New-Object System.Drawing.Font("Consolas", 9)
$script:logBox.ReadOnly      = $true
$script:logBox.Text          = ""
$form.Controls.Add($script:logBox); New-Row 4

# -- Buttons ---------------------------------------------------------
$btnY = $form.ClientSize.Height - 50

$cancelBtn = New-Object System.Windows.Forms.Button
$cancelBtn.Location     = MkPt 215 $btnY
$cancelBtn.Size          = MkSz 90 30
$cancelBtn.Text         = "Cancel"
$cancelBtn.DialogResult = $([System.Windows.Forms.DialogResult]::Cancel)
$form.Controls.Add($cancelBtn)

$procBtn = New-Object System.Windows.Forms.Button
$procBtn.Location     = MkPt 310 $btnY
$procBtn.Size          = MkSz 110 30
$procBtn.Text         = "&Process"
$form.Controls.Add($procBtn)

# --- Processing function ------------------------------------------
function Process-Folder {
    # Disable UI during processing
    $browseBtn.Enabled   = $false
    $procBtn.Enabled     = $false
    $chkNumbers.Enabled  = $false
    $chkWatermark.Enabled = $false
    $txtWidth.Enabled    = $false
    $txtFontSize.Enabled = $false
    $txtOpacity.Enabled  = $false
    $txtStartAt.Enabled  = $false
    $script:logBox.Text  = ""

    try {
        $doNumbers   = $chkNumbers.Checked
        $doWatermark = $chkWatermark.Checked

        if (-not $doNumbers -and -not $doWatermark) {
            [System.Windows.Forms.MessageBox]::Show("Please select at least one option.", "Nothing to do")
            return
        }
        if ([string]::IsNullOrWhiteSpace($selPath)) {
            [System.Windows.Forms.MessageBox]::Show("No folder selected. Please use Browse first.", "No folder")
            return
        }

        # Parse numeric settings (fall back to defaults on bad input)
        $tgtW = $DEFAULT_TARGET_WIDTH
        if (-not ([int]::TryParse($txtWidth.Text, [ref]$tgtW)) -or $tgtW -le 0) {
            $tgtW = $DEFAULT_TARGET_WIDTH
        }

        $fntSz = $DEFAULT_FONT_SIZE
        if (-not ([int]::TryParse($txtFontSize.Text, [ref]$fntSz)) -or $fntSz -le 0) {
            $fntSz = $DEFAULT_FONT_SIZE
        }

        $opac = $DEFAULT_OPACITY
        if (-not ([float]::TryParse($txtOpacity.Text, [ref]$opac))) {
            $opac = $DEFAULT_OPACITY
        }
        $opac = [math]::Max(0.0, [math]::Min(1.0, $opac))

        # -- Pre-flight checks ---------------------------------------
        try {
            Get-Command magick -ErrorAction Stop | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("magick (ImageMagick) not found on PATH.
Please install ImageMagick and ensure 'magick' is available.", "Missing dependency")
            return
        }

        # Resolve watermark assets relative to script location
        $waterDir  = Join-Path $scriptRoot "angled_watermark"
        $wmShaded  = Join-Path $waterDir "watermark-shaded.png"
        $wmOutline = Join-Path $waterDir "watermark-outline.png"

        if ($doWatermark -and (-not (Test-Path $wmShaded) -or -not (Test-Path $wmOutline))) {
            [System.Windows.Forms.MessageBox]::Show(
                "Watermark assets not found.
Expected:
  $wmShaded
  $wmOutline",
                "Missing files"
            )
            return
        }

        # Parse starting sequence number
        $startSeq = 1
        if (-not ([int]::TryParse($txtStartAt.Text, [ref]$startSeq)) -or $startSeq -lt 0) {
            $startSeq = 1
        }

        # -- Output directory -------------------
        $inDir  = $selPath
        $outDir = Join-Path $inDir "Processed"

        if ($outDir.StartsWith($inDir)) {
            if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
        }
        New-Item -ItemType Directory -Path $outDir | Out-Null

        Log-Output "Processing folder: $inDir"
        Log-Output ("-" * 50)

        # -- Process files -------------------------------------------
        $s = $startSeq
        $tot = (Get-ChildItem $inDir -File | Where-Object {
            $FILE_TYPES -contains $_.Extension.TrimStart('.').ToLower()
        }).Count
        $dig = [math]::Max(2, "$tot".Length)

        foreach ($file in Get-ChildItem $inDir -File | Sort-Object Name) {
            $ext  = $file.Extension.TrimStart('.').ToLower()
            if ($FILE_TYPES -notcontains $ext) { continue }

            $srcFile   = $file.FullName
            $n         = "{0:D$dig}" -f $s
            $origBasename = $file.BaseName
            if ($doNumbers) {
                $dstName = "$n-$origBasename.jpg"
            } else {
                $dstName = $file.Name
            }
            $dstFile   = Join-Path $outDir $dstName

            $tmpResize  = Join-Path $outDir "__tmp_resize.png"
            $tmpNumbers = Join-Path $outDir "__tmp_numbers.png"
            $tmpWm1     = Join-Path $outDir "__tmp_wm1.png"
            $tmpWm2     = Join-Path $outDir "__tmp_wm2.png"
            $tmpSliced  = Join-Path $outDir "__tmp_sliced.png"

            Log-Output "[$n/$tot] $($file.Name)"
            $form.Refresh()

            try {
                magick "$srcFile" -auto-orient "$tmpResize"

                $dims  = Get-ImageDimensions $tmpResize
                $origW = $dims.Width
                $origH = $dims.Height
                $newH  = [math]::Round(($origH / $origW) * $tgtW)
                $res   = "{0}x{1}" -f $tgtW, $newH

                if ($doNumbers) {
                    magick "$tmpResize" -resize $res `
                        -gravity SouthEast `
                        -fill "rgba(0,0,0,0.6)" `
                        -draw "roundRectangle $($tgtW-($fntSz*6/5)),$($newH-($fntSz*5/4)),$($tgtW-10),$($newH-10),15,15" `
                        -fill white -font Arial -pointsize $fntSz `
                        -annotate +10+10 "$s." `
                        "$tmpNumbers"
                    Remove-Item $tmpResize
                }

                if ($doWatermark) {
                    if (-not $doNumbers) {
                        magick "$tmpResize" -resize $res "$tmpSliced"
                        Remove-Item $tmpResize
                    }

                    if ($origH -gt $origW) {
                        $wmSize = "{0}x{0}" -f $newH
                    } else {
                        $wmSize = "{0}x{0}" -f $tgtW
                    }

                    magick "$wmShaded"  -resize $wmSize "$tmpWm1"
                    magick "$wmOutline" -resize $wmSize `
                        -background none -alpha set -channel A -evaluate Multiply $opac `
                        "$tmpWm2"

                    if ($doNumbers) {
                        magick "$tmpNumbers" "$tmpWm1" -gravity center -compose SoftLight `
                            -composite "$tmpSliced"
                        magick "$tmpSliced" "$tmpWm2" -gravity center -compose HardLight `
                            -composite "$dstFile"
                    } else {
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
                Log-Output "WARNING: Skipping '$($file.Name)': $($_.Exception.Message)" warn
            } finally {
                Get-ChildItem $outDir -Filter "__tmp_*" | Remove-Item -Force -ErrorAction SilentlyContinue
            }

            $s++
        }

        Log-Output ("-" * 50)
        Log-Output "Done. Output: $outDir"
    } finally {
        # Re-enable UI
        $browseBtn.Enabled   = $true
        $procBtn.Enabled     = $true
        $chkNumbers.Enabled  = $true
        $chkWatermark.Enabled = $true
        $txtWidth.Enabled    = $true
        $txtFontSize.Enabled = $true
        $txtOpacity.Enabled  = $true
        $txtStartAt.Enabled  = $true
    }
}

# --- Process button click handler ----------------------------------
$procBtn.Add_Click({
    Process-Folder
})

# --- Show form ------------------------------------------------------
$form.ShowDialog()
exit
