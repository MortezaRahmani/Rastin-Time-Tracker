$ErrorActionPreference = 'Stop'

$appName = 'RTT'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\RTT'
$dataDir = Join-Path $env:APPDATA 'RTT'
$shortcutDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RTT'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Rastin Time Tracker.lnk'
$payload = Join-Path $PSScriptRoot 'payload.zip'

New-Item -ItemType Directory -Force -Path $installDir, $dataDir, $shortcutDir | Out-Null
Expand-Archive -LiteralPath $payload -DestinationPath $installDir -Force

$exe = Join-Path $installDir 'rastin_time_tracker.exe'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $shortcutDir 'Rastin Time Tracker.lnk'))
$shortcut.TargetPath = $exe
$shortcut.WorkingDirectory = $installDir
$shortcut.IconLocation = "$exe,0"
$shortcut.Save()

$desktop = $shell.CreateShortcut($desktopShortcut)
$desktop.TargetPath = $exe
$desktop.WorkingDirectory = $installDir
$desktop.IconLocation = "$exe,0"
$desktop.Save()

$uninstaller = Join-Path $installDir 'uninstall.ps1'
@'
$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\RTT'
$shortcutDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RTT'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Rastin Time Tracker.lnk'
Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $shortcutDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'RTT was uninstalled. Your database remains in %APPDATA%\RTT.'
'@ | Set-Content -LiteralPath $uninstaller -Encoding UTF8

$uninstallCmd = Join-Path $installDir 'Uninstall RTT.cmd'
"@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$uninstaller""`r`npause`r`n" |
  Set-Content -LiteralPath $uninstallCmd -Encoding ASCII

Start-Process -FilePath $exe
