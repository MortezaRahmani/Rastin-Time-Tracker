$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot '..\app'
Push-Location $app
flutter build windows --release
$output = Join-Path $PSScriptRoot '..\releases\rtt-windows-portable'
New-Item -ItemType Directory -Force -Path $output | Out-Null
Copy-Item 'build\windows\x64\runner\Release\*' $output -Recurse -Force
Pop-Location
