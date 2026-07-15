$newWidth = 1280
$fontScale = 100
$opasity = 0.6
$fileTypes = "png", "jpg", "bmp"
$waterDir = "angled_watermark"
$watermark = "$waterDir\watermark-shaded.png"
$watermark2 = "$waterDir\watermark-outline.png"

Add-Type -AssemblyName System.Windows.Forms

$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select a folder with pictures"
$folderBrowser.RootFolder = [Environment+SpecialFolder]::Desktop
$folderBrowser.ShowNewFolderButton = $false

$result = $folderBrowser.ShowDialog()

function Get-ImageDimensions($filePath) {
    $output = & magick identify $filePath
    if ($output -match '(\d+)x(\d+)') {
        return @{
            Width = $matches[1]
            Height = $matches[2]
        }
    } else {
        throw "Failed to parse dimensions from: $output"
    }
}

if ($result -eq [Windows.Forms.DialogResult]::OK) {
	$inDir = $folderBrowser.SelectedPath
	
	$inDirName = Split-Path $inDir -Leaf
	$inDirParent = Split-Path $inDir -Parent
	$outDir = Join-Path $inDirParent ("${inDirName}_Watermarked")
	
	if (Test-Path -Path $outDir) { Remove-Item -Force -R -Path $outDir }
	New-Item -ItemType Directory -Path $outDir

	Get-ChildItem $inDir | Sort-Object Name | ForEach-Object {
	$file = $_
		$fileEnd = $file.Extension.TrimStart('.').ToLower()
		if ($fileTypes -contains $fileEnd) {
			$inFile = "$inDir\$file"
			$baseFile = $file.BaseName
			$outFile = "$outDir\$baseFile-watermarked.jpg"

			# Additions
			$tempFile = "$outDir\tmp.jpg"
			$tempFile2 = "$outDir\tmp2.jpg"
			$tempWaterFile = "$outDir\water-tmp.jpg"
			$tempWaterFile2 = "$outDir\water-tmp2.png"
			magick convert "$inFile" -auto-orient "$tempFile"

			$dimensions = Get-ImageDimensions $tempFile
			$orgWidth = $dimensions.Width
			$orgHeight = $dimensions.Height
			
			if ($orgHeight -gt $orgWidth) {
				magick convert "$watermark" -resize ${newWidth}x${newWidth} "$tempWaterFile"
#				magick convert "$watermark2" -resize ${newWidth}x${newWidth} -background none "$tempWaterFile2"
				magick convert "$watermark2" -resize ${newWidth}x${newWidth} -background none -alpha set -channel A -evaluate Multiply $opasity "$tempWaterFile2"
			} else {
				magick convert "$watermark" -resize ${newHeight}x${newHeight} "$tempWaterFile"
#				magick convert "$watermark2" -resize ${newHeight}x${newHeight} -background none "$tempWaterFile2"
				magick convert "$watermark2" -resize ${newHeight}x${newHeight} -background none -alpha set -channel A -evaluate Multiply $opasity "$tempWaterFile2"
			}


			
			$newH1 = ($orgHeight / $orgWidth) * $newWidth
			$newHeight = [math]::Round($newH1)

			$resolution = "${newWidth}x${newHeight}"

			Write-Host " [ Creating watermarked file -> $outFile ]"
			magick convert "$tempFile" -resize $resolution "$tempWaterFile" -gravity center -compose SoftLight -composite $tempFile2
			magick convert "$tempFile2" -resize $resolution "$tempWaterFile2" -gravity center -compose HardLight -composite "$outFile"

			Remove-Item -Path $tempFile
			Remove-Item -Path $tempFile2
			Remove-Item -Path $tempWaterFile
			Remove-Item -Path $tempWaterFile2
		}
	}
}
else {
	Write-Host "No folder was selected"
}

# Read-Host -Prompt "Press Enter to continue"