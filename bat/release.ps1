# WinCMP Automated Release Script
# Ensure Console output encoding is UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "     WinCMP Automated Release Wizard " -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

# 1. Get project paths
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path -Path $ScriptDir -Parent
Set-Location -Path $ProjectRoot

Write-Host "[1] Reading Version from FyneApp.toml..." -ForegroundColor Gray
$FyneAppPath = Join-Path $ProjectRoot "FyneApp.toml"
if (-not (Test-Path $FyneAppPath)) {
    Write-Error "FyneApp.toml not found! Make sure you run this script within the WinCMP project."
}

$FyneAppContent = Get-Content $FyneAppPath -Raw
if ($FyneAppContent -match 'Version\s*=\s*"([^"]+)"') {
    $Version = $Matches[1]
    Write-Host "    -> Version detected: v$Version" -ForegroundColor Green
} else {
    Write-Error "Failed to parse Version from FyneApp.toml!"
}

# 1.1 Backup FyneApp.toml to prevent Git dirty changes from 'fyne package -release'
$FyneAppBackup = $null
if (Test-Path $FyneAppPath) {
    $FyneAppBackup = Get-Content $FyneAppPath -Raw
    Write-Host "    -> Cached FyneApp.toml contents to restore Build number later" -ForegroundColor DarkGray
}

# 2. Compile release build using Fyne (or Go fallback)
Write-Host "[2] Compiling release build with Icon..." -ForegroundColor Gray

# Check if 'fyne' CLI is available
$HasFyne = $false
$fyneCheck = Get-Command "fyne" -ErrorAction SilentlyContinue
if ($fyneCheck) {
    $HasFyne = $true
}

$BuildFailed = $false
try {
    if ($HasFyne) {
        Write-Host "    -> Fyne CLI detected. Packaging using 'fyne package -release'..." -ForegroundColor DarkGray
        fyne package -release
        Write-Host "    -> Fyne package build succeeded!" -ForegroundColor Green
    } else {
        Write-Host "    -> Fyne CLI not found. Falling back to standard 'go build'..." -ForegroundColor Yellow
        go build -ldflags "-H windowsgui -s -w" -o wincmp.exe .
        Write-Host "    -> Go build succeeded!" -ForegroundColor Green
    }
} catch {
    $BuildFailed = $true
    Write-Error "Compilation failed! Please check your Go, Fyne, or GCC configuration."
} finally {
    # Restore FyneApp.toml to keep git state clean
    if ($FyneAppBackup) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($FyneAppPath, $FyneAppBackup, $utf8NoBom)
        Write-Host "    -> Restored FyneApp.toml to its original state (clean git status)" -ForegroundColor Green
    }
}

if ($BuildFailed) {
    exit 1
}

# 3. Prepare release folder structure
$ReleaseParentDir = Join-Path (Split-Path -Path $ProjectRoot -Parent) "wincmp-release-only"
$ReleaseDirName = "wincmp_v$Version"
$TargetDir = Join-Path $ReleaseParentDir $ReleaseDirName

Write-Host "[3] Preparing clean release directory..." -ForegroundColor Gray
Write-Host "    -> Release Parent: $ReleaseParentDir" -ForegroundColor DarkGray
Write-Host "    -> Target Directory: $TargetDir" -ForegroundColor DarkGray

if (-not (Test-Path $ReleaseParentDir)) {
    New-Item -ItemType Directory -Path $ReleaseParentDir -Force | Out-Null
}

if (Test-Path $TargetDir) {
    Write-Host "    -> Target directory already exists, cleaning old files..." -ForegroundColor Yellow
    Remove-Item -Path $TargetDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

# 4. Copy template files
Write-Host "[4] Copying release template..." -ForegroundColor Gray
$TemplateDir = Join-Path $ProjectRoot "packaging\wincmp"
if (-not (Test-Path $TemplateDir)) {
    Write-Error "Template directory packaging\wincmp not found!"
}

# Copy structure
Copy-Item -Path "$TemplateDir\*" -Destination $TargetDir -Recurse -Force

# 5. Copy and rename executable
Write-Host "[5] Copying and renaming executable..." -ForegroundColor Gray
$BuiltExe = Join-Path $ProjectRoot "wincmp.exe"
if (-not (Test-Path $BuiltExe)) {
    $BuiltExe = Join-Path $ProjectRoot "WinCMP.exe"
}
$TargetExe = Join-Path $TargetDir "WinCMP_v$Version.exe"

if (-not (Test-Path $BuiltExe)) {
    Write-Error "Could not find built wincmp.exe or WinCMP.exe!"
}
Copy-Item -Path $BuiltExe -Destination $TargetExe -Force
Write-Host "    -> Created executable: WinCMP_v$Version.exe" -ForegroundColor Green

# 6. Clean redundant files (.gitkeep, .example, logs, backups, etc.)
Write-Host "[6] Cleaning redundant and test files..." -ForegroundColor Gray

# Remove .gitkeep files
$Gitkeeps = Get-ChildItem -Path $TargetDir -Filter ".gitkeep" -Recurse -Force
if ($Gitkeeps) {
    $Gitkeeps | Remove-Item -Force
    Write-Host "    -> Cleaned $($Gitkeeps.Count) .gitkeep files" -ForegroundColor DarkGray
}

# Remove .example files
$Examples = Get-ChildItem -Path $TargetDir -Filter "*.example" -Recurse -Force
if ($Examples) {
    $Examples | Remove-Item -Force
    Write-Host "    -> Cleaned $($Examples.Count) .example files" -ForegroundColor DarkGray
}

# Empty logs
$LogsPath = Join-Path $TargetDir "logs"
if (Test-Path $LogsPath) {
    Get-ChildItem -Path $LogsPath -File -Force | Remove-Item -Force
    Write-Host "    -> Cleared logs/ directory" -ForegroundColor DarkGray
}

# Clean data subfolders contents but keep the folder structure
$DataPath = Join-Path $TargetDir "data"
if (Test-Path $DataPath) {
    $SubDirs = Get-ChildItem -Path $DataPath -Directory -Recurse -Force
    foreach ($dir in $SubDirs) {
        Get-ChildItem -Path $dir.FullName -File -Recurse -Force | Remove-Item -Force
    }
    Write-Host "    -> Cleared data/ subdirectory contents" -ForegroundColor DarkGray
}

# 7. Verify required release files
Write-Host "[7] Verifying required documentation..." -ForegroundColor Gray
$RequiredFiles = @("readme.md", "CHANGELOG.md", "LICENSE")
$MissingFiles = @()

foreach ($file in $RequiredFiles) {
    $checkPath = Join-Path $TargetDir $file
    if (-not (Test-Path $checkPath)) {
        $MissingFiles += $file
    }
}

if ($MissingFiles.Count -gt 0) {
    Write-Host "    ⚠️ Warning! Missing files: $($MissingFiles -join ', ')" -ForegroundColor Yellow
} else {
    Write-Host "    -> All required documentation verified!" -ForegroundColor Green
}

# 8. Compress release files
Write-Host "[8] Compressing release package..." -ForegroundColor Gray

# Look for 7z.exe
$7zPaths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe"
)
$7zExe = $null

foreach ($p in $7zPaths) {
    if (Test-Path $p) {
        $7zExe = $p
        break
    }
}

if (-not $7zExe) {
    $cmdCheck = Get-Command "7z" -ErrorAction SilentlyContinue
    if ($cmdCheck) {
        $7zExe = "7z"
    }
}

if ($7zExe) {
    $ZipFile = Join-Path $ReleaseParentDir "wincmp_v$Version.7z"
    if (Test-Path $ZipFile) {
        Remove-Item -Path $ZipFile -Force
    }
    Write-Host "    -> 7-Zip found. Compressing to .7z..." -ForegroundColor DarkGray
    
    # Change location to keep relative path structure in archive
    Set-Location -Path $ReleaseParentDir
    & $7zExe a -t7z $ZipFile $ReleaseDirName -mx5 | Out-Null
    
    Write-Host "    -> Successfully generated: $ZipFile" -ForegroundColor Green
} else {
    # Fallback to Compress-Archive
    $ZipFile = Join-Path $ReleaseParentDir "wincmp_v$Version.zip"
    if (Test-Path $ZipFile) {
        Remove-Item -Path $ZipFile -Force
    }
    Write-Host "    -> 7-Zip not found. Using PowerShell Compress-Archive for .zip fallback..." -ForegroundColor Yellow
    
    Set-Location -Path $ReleaseParentDir
    Compress-Archive -Path $ReleaseDirName -DestinationPath $ZipFile -Force
    Write-Host "    -> Successfully generated: $ZipFile" -ForegroundColor Green
}

# Return to root
Set-Location -Path $ProjectRoot

Write-Host "===================================================" -ForegroundColor Green
Write-Host "✨ Automated release completed successfully!" -ForegroundColor Green
Write-Host "Saved to: $ZipFile" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
