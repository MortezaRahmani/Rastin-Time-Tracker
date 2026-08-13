Unicode true
ManifestSupportedOS all
RequestExecutionLevel user

!define APP_NAME "Rastin Time Tracker Portable"
!define APP_EXE "rastin_time_tracker.exe"
!define APP_VERSION "1.0.0"
!define SOURCE_DIR "..\..\app\build\windows\x64\runner\Release"
!define OUT_FILE "..\..\releases\windows\RTT-Windows-Portable-x64.exe"

!include "MUI2.nsh"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$DESKTOP\RTT-Portable"

!define MUI_ABORTWARNING
!define MUI_ICON "..\..\app\windows\runner\resources\app_icon.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Section "Extract portable app" SecPortable
  SetOutPath "$INSTDIR"
  File /r "${SOURCE_DIR}\*.*"
  FileOpen $0 "$INSTDIR\portable.flag" w
  FileClose $0
SectionEnd
