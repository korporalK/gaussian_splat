# COLMAP 4.0.2 Update Script for Windows

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$RootDir = (Resolve-Path "$PSScriptRoot\..").Path
$ZipUrl = "https://github.com/colmap/colmap/releases/download/4.0.2/colmap-x64-windows-cuda.zip"
$ZipPath = "$RootDir\colmap-4.0.2.zip"
$DestDir = "$RootDir\colmap"
$TempExtract = "$RootDir\colmap-temp"

Write-Output "=== Downloading COLMAP 4.0.2 (CUDA) ==="
Write-Output "URL: $ZipUrl"
Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath
Write-Output "Download completed!"

Write-Output "=== Extracting COLMAP 4.0.2 ==="
if (Test-Path $TempExtract) {
    Remove-Item -Path $TempExtract -Recurse -Force
}
New-Item -ItemType Directory -Path $TempExtract | Out-Null
Expand-Archive -Path $ZipPath -DestinationPath $TempExtract
Write-Output "Extraction completed!"

Write-Output "=== Replacing old COLMAP folder ==="
# Kill any processes that might lock the old colmap folder
Get-Process -Name "colmap" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path $DestDir) {
    Remove-Item -Path $DestDir -Recurse -Force
}

# The ZIP contains a root folder named like colmap-x64-windows-cuda or similar
$SubDirs = Get-ChildItem -Path $TempExtract -Directory
if ($SubDirs.Count -eq 1) {
    # Move the subfolder contents directly to $DestDir
    Move-Item -Path $SubDirs[0].FullName -Destination $DestDir
} else {
    # Move the temp folder directly to $DestDir
    Move-Item -Path $TempExtract -Destination $DestDir
}

# Clean up
if (Test-Path $TempExtract) {
    Remove-Item -Path $TempExtract -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path $ZipPath) {
    Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue
}

Write-Output "=== Verifying New COLMAP Version ==="
$ColmapExe = "$DestDir\bin\colmap.exe"
if (Test-Path $ColmapExe) {
    & $ColmapExe help | Out-String | Select-String -Pattern "COLMAP" | Select-Object -First 1
    Write-Output "COLMAP 4.0.2 successfully installed!"
} else {
    Write-Error "Verification failed: colmap.exe not found at $ColmapExe"
}
