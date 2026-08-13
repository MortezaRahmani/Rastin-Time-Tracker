$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..\app')
flutter build apk --release
Pop-Location
