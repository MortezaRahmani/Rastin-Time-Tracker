# Release builds

- Windows portable: `powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1`
- Android APK: `powershell -ExecutionPolicy Bypass -File scripts/build-android.ps1`
- macOS: on macOS, run `flutter build macos`.
- Linux: on Linux, run `flutter build linux`.

Create native installers on their target operating systems after signing is configured. Do not distribute unsigned production installers.
