Add-Type -AssemblyName System.Windows.Forms

$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select Folder with Pictures"
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
	$outDir = Join-Path $inDirParent ("${inDirName}_Numbered")
	
    $newWidth = 1280
    $fontSize = 160
    $fileTypes = "png", "jpg", "bmp"

    if (!(Test-Path -Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir
    }

	$numb = 1
	Get-ChildItem $inDir | Sort-Object Name | ForEach-Object {
	$file = $_
		$fileEnd = $file.Extension.TrimStart('.').ToLower()
		if ($fileTypes -contains $fileEnd) {
			$fileName = $file.BaseName.ToLower()
			$fNumb = "{0:D2}" -f $numb
			$inFile = "$inDir\$file"
			$outFile = "$outDir\puke-$fNumb.jpg"

			$tempFile = "$outDir\temp.jpg"
			magick convert $inFile -auto-orient $tempFile

			$dimensions = Get-ImageDimensions $tempFile
			$orgWidth = $dimensions.Width
			$orgHeight = $dimensions.Height
			
			$newH1 = ($orgHeight / $orgWidth) * $newWidth
			$newHeight = [math]::Round($newH1)

			$resolution = "${newWidth}x${newHeight}"
			$xMin = $newWidth - ($fontSize * 6 / 5)
			$yMin = $newHeight - ($fontSize * 5 / 4)
			$xMax = $newWidth - 10
			$yMax = $newHeight - 10
			Write-Host "[ $fNumb | Adding number to $file -> $outFile ]"
			magick convert $tempFile -auto-orient -resize $resolution -gravity SouthEast -fill "rgba(0,0,0,0.6)" -draw "roundRectangle $xMin,$yMin,$xMax,$yMax,15,15" -fill white -font Arial -pointsize $fontSize -annotate +10+10 "${numb}." $outFile
			Remove-Item $tempFile
			$numb++
		}
	}
}
else {
	Write-Host "No folder was selected"
}
