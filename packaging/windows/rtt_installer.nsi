Unicode true
ManifestSupportedOS all
RequestExecutionLevel user

!define APP_NAME "Rastin Time Tracker"
!define APP_SHORT_NAME "RTT"
!define APP_EXE "rastin_time_tracker.exe"
!define APP_VERSION "1.0.0"
!define SOURCE_DIR "..\..\app\build\windows\x64\runner\Release"
!define OUT_FILE "..\..\SHARE\RTT-Windows-Setup-NSIS.exe"

!include "MUI2.nsh"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\RTT"
InstallDirRegKey HKCU "Software\RTT" "InstallDir"

!define MUI_ABORTWARNING
!define MUI_ICON "..\..\app\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\..\app\windows\runner\resources\app_icon.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install" SecInstall
  SetOutPath "$INSTDIR"
  File /r "${SOURCE_DIR}\*.*"

  CreateDirectory "$APPDATA\RTT"
  CreateDirectory "$SMPROGRAMS\RTT"
  CreateShortcut "$SMPROGRAMS\RTT\Rastin Time Tracker.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$DESKTOP\Rastin Time Tracker.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

  WriteUninstaller "$INSTDIR\Uninstall RTT.exe"
  WriteRegStr HKCU "Software\RTT" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RTT" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RTT" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RTT" "Publisher" "Rastin"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RTT" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RTT" "UninstallString" '"$INSTDIR\Uninstall RTT.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RTT" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RTT" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\Rastin Time Tracker.lnk"
  Delete "$SMPROGRAMS\RTT\Rastin Time Tracker.lnk"
  RMDir "$SMPROGRAMS\RTT"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\RTT"
  DeleteRegKey HKCU "Software\RTT"

  RMDir /r "$INSTDIR"
SectionEnd
