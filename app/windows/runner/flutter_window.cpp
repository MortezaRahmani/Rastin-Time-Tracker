#include "flutter_window.h"

#include <optional>
#include <chrono>
#include <iomanip>
#include <mmsystem.h>
#include <shellapi.h>
#include <sstream>
#include <shobjidl.h>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

#include <flutter/standard_method_codec.h>

#pragma comment(lib, "winmm.lib")
#pragma comment(lib, "shell32.lib")

namespace {

std::wstring ExeDirectory() {
  wchar_t path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) return std::wstring();
  std::wstring value(path, length);
  const auto slash = value.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring() : value.substr(0, slash);
}

std::wstring DefaultReminderSoundPath() {
  const auto directory = ExeDirectory();
  if (directory.empty()) return std::wstring();
  return directory + L"\\data\\flutter_assets\\assets\\audio\\breaktime.mp3";
}

bool PlaySoundFile(const std::wstring& path) {
  if (path.empty() || ::GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  ::mciSendStringW(L"close rtt_break_sound", nullptr, 0, nullptr);
  const std::wstring open = L"open \"" + path + L"\" alias rtt_break_sound";
  if (::mciSendStringW(open.c_str(), nullptr, 0, nullptr) != 0) return false;
  return ::mciSendStringW(L"play rtt_break_sound", nullptr, 0, nullptr) == 0;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  title_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "rtt/window",
          &flutter::StandardMethodCodec::GetInstance());
  title_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "chooseExportFolder") {
          IFileOpenDialog* dialog = nullptr;
          if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                        CLSCTX_ALL, IID_PPV_ARGS(&dialog)))) {
            result->Error("folder-picker", "Could not open the folder picker.");
            return;
          }
          DWORD options = 0;
          dialog->GetOptions(&options);
          dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                             FOS_PATHMUSTEXIST);
          if (FAILED(dialog->Show(GetHandle()))) {
            dialog->Release();
            result->Success(flutter::EncodableValue());
            return;
          }
          IShellItem* item = nullptr;
          PWSTR path = nullptr;
          const HRESULT item_result = dialog->GetResult(&item);
          const HRESULT path_result = SUCCEEDED(item_result)
              ? item->GetDisplayName(SIGDN_FILESYSPATH, &path)
              : E_FAIL;
          if (item != nullptr) item->Release();
          dialog->Release();
          if (FAILED(path_result)) {
            result->Error("folder-picker", "Could not read the selected folder.");
            return;
          }
          const auto folder = Utf8FromUtf16(path);
          ::CoTaskMemFree(path);
          result->Success(flutter::EncodableValue(folder));
          return;
        }
        if (call.method_name() == "chooseLocalDatabaseFile") {
          IFileOpenDialog* dialog = nullptr;
          if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                        CLSCTX_ALL, IID_PPV_ARGS(&dialog)))) {
            result->Error("file-picker", "Could not open the file picker.");
            return;
          }
          COMDLG_FILTERSPEC filters[] = {
              {L"SQLite databases", L"*.sqlite;*.sqlite3;*.db"},
              {L"All files", L"*.*"},
          };
          dialog->SetFileTypes(2, filters);
          dialog->SetFileTypeIndex(1);
          DWORD options = 0;
          dialog->GetOptions(&options);
          dialog->SetOptions(options | FOS_FORCEFILESYSTEM |
                             FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST);
          if (FAILED(dialog->Show(GetHandle()))) {
            dialog->Release();
            result->Success(flutter::EncodableValue());
            return;
          }
          IShellItem* item = nullptr;
          PWSTR path = nullptr;
          const HRESULT item_result = dialog->GetResult(&item);
          const HRESULT path_result = SUCCEEDED(item_result)
              ? item->GetDisplayName(SIGDN_FILESYSPATH, &path)
              : E_FAIL;
          if (item != nullptr) item->Release();
          dialog->Release();
          if (FAILED(path_result)) {
            result->Error("file-picker", "Could not read the selected file.");
            return;
          }
          const auto file = Utf8FromUtf16(path);
          ::CoTaskMemFree(path);
          result->Success(flutter::EncodableValue(file));
          return;
        }
        if (call.method_name() == "chooseReminderSoundFile") {
          IFileOpenDialog* dialog = nullptr;
          if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                        CLSCTX_ALL, IID_PPV_ARGS(&dialog)))) {
            result->Error("file-picker", "Could not open the file picker.");
            return;
          }
          COMDLG_FILTERSPEC filters[] = {
              {L"Audio files", L"*.mp3;*.wav;*.ogg"},
              {L"All files", L"*.*"},
          };
          dialog->SetFileTypes(2, filters);
          dialog->SetFileTypeIndex(1);
          DWORD options = 0;
          dialog->GetOptions(&options);
          dialog->SetOptions(options | FOS_FORCEFILESYSTEM |
                             FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST);
          if (FAILED(dialog->Show(GetHandle()))) {
            dialog->Release();
            result->Success(flutter::EncodableValue());
            return;
          }
          IShellItem* item = nullptr;
          PWSTR path = nullptr;
          const HRESULT item_result = dialog->GetResult(&item);
          const HRESULT path_result = SUCCEEDED(item_result)
              ? item->GetDisplayName(SIGDN_FILESYSPATH, &path)
              : E_FAIL;
          if (item != nullptr) item->Release();
          dialog->Release();
          if (FAILED(path_result)) {
            result->Error("file-picker", "Could not read the selected file.");
            return;
          }
          const auto file = Utf8FromUtf16(path);
          ::CoTaskMemFree(path);
          result->Success(flutter::EncodableValue(file));
          return;
        }
        if (call.method_name() == "playReminderSound") {
          std::wstring path = DefaultReminderSoundPath();
          const auto* arguments = call.arguments() == nullptr
              ? nullptr
              : std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments != nullptr) {
            const auto path_it = arguments->find(flutter::EncodableValue("path"));
            const auto* custom_path = path_it == arguments->end()
                ? nullptr
                : std::get_if<std::string>(&path_it->second);
            if (custom_path != nullptr && !custom_path->empty()) {
              path = Utf16FromUtf8(*custom_path);
            }
          }
          if (!PlaySoundFile(path)) {
            result->Error("sound", "Could not play the reminder sound.");
            return;
          }
          result->Success();
          return;
        }
        if (call.method_name() == "stopReminderSound") {
          ::mciSendStringW(L"close rtt_break_sound", nullptr, 0, nullptr);
          result->Success();
          return;
        }
        if (call.method_name() == "setMinimizeToTray") {
          const auto* enabled = call.arguments() == nullptr
              ? nullptr
              : std::get_if<bool>(call.arguments());
          if (enabled == nullptr) {
            result->Error("invalid-arguments", "A boolean value is required.");
            return;
          }
          SetMinimizeToTray(*enabled);
          result->Success();
          return;
        }
        if (call.method_name() == "showWindow") {
          RestoreFromTray();
          result->Success();
          return;
        }
        if (call.method_name() == "exitApp") {
          RemoveTrayIcon();
          ::PostMessage(GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
          return;
        }
        if (call.method_name() == "startTrackingTitle") {
          const auto* arguments = call.arguments() == nullptr
              ? nullptr
              : std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("invalid-arguments", "Tracking details are required.");
            return;
          }
          const auto started_it = arguments->find(flutter::EncodableValue("startedAt"));
          const auto* started_at = started_it == arguments->end()
              ? nullptr : std::get_if<int64_t>(&started_it->second);
          const auto paused_it = arguments->find(flutter::EncodableValue("pausedSeconds"));
          const auto* paused_seconds = paused_it == arguments->end()
              ? nullptr : std::get_if<int64_t>(&paused_it->second);
          if (started_at == nullptr) {
            result->Error("invalid-arguments", "Start time is required.");
            return;
          }
          StartTrackingTitle(*started_at, paused_seconds == nullptr ? 0 : *paused_seconds);
          result->Success();
          return;
        }
        if (call.method_name() != "setTitle") {
          result->NotImplemented();
          return;
        }
        const auto* title = call.arguments() == nullptr
                                ? nullptr
                                : std::get_if<std::string>(call.arguments());
        if (title == nullptr) {
          result->Error("invalid-arguments", "A title string is required.");
          return;
        }
        StopTrackingTitle();
        ::SetWindowTextW(GetHandle(), Utf16FromUtf8(*title).c_str());
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  StopTrackingTitle();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_TIMER && wparam == kTrackingTimerId) {
    UpdateTrackingTitle();
    return 0;
  }
  if (message == kTrayIconMessage) {
    if (lparam == WM_LBUTTONUP ||
        lparam == WM_LBUTTONDBLCLK ||
        lparam == NIN_SELECT ||
        lparam == NIN_KEYSELECT) {
      RestoreFromTray();
    } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      ShowTrayMenu();
    }
    return 0;
  }
  if (message == WM_SIZE && wparam == SIZE_MINIMIZED && minimize_to_tray_) {
    ::ShowWindow(GetHandle(), SW_HIDE);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrayShowWindowCommand:
          RestoreFromTray();
          return 0;
        case kTrayExitCommand:
          RemoveTrayIcon();
          ::PostMessage(GetHandle(), WM_CLOSE, 0, 0);
          return 0;
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::StartTrackingTitle(int64_t started_at, int64_t paused_seconds) {
  tracking_started_at_ = std::chrono::system_clock::time_point(
      std::chrono::milliseconds(started_at));
  tracking_paused_seconds_ = paused_seconds < 0 ? 0 : paused_seconds;
  UpdateTrackingTitle();
  ::SetTimer(GetHandle(), kTrackingTimerId, 1000, nullptr);
}

void FlutterWindow::StopTrackingTitle() {
  ::KillTimer(GetHandle(), kTrackingTimerId);
}

void FlutterWindow::UpdateTrackingTitle() {
  const auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
      std::chrono::system_clock::now() - tracking_started_at_).count();
  const auto worked = elapsed - tracking_paused_seconds_;
  const auto total = worked < 0 ? 0 : worked;
  std::wostringstream title;
  title << L"RTT \u2022 " << std::setfill(L'0') << std::setw(2) << total / 3600
        << L":" << std::setw(2) << (total / 60) % 60 << L":"
        << std::setw(2) << total % 60;
  ::SetWindowTextW(GetHandle(), title.str().c_str());
}

void FlutterWindow::SetMinimizeToTray(bool enabled) {
  minimize_to_tray_ = enabled;
  if (!enabled) RemoveTrayIcon();
}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_visible_) return;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayIconMessage;
  data.hIcon = ::LoadIcon(::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"Rastin Time Tracker");
  if (::Shell_NotifyIconW(NIM_ADD, &data)) {
    data.uVersion = NOTIFYICON_VERSION_4;
    ::Shell_NotifyIconW(NIM_SETVERSION, &data);
    tray_icon_visible_ = true;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_visible_) return;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
  tray_icon_visible_ = false;
}

void FlutterWindow::RestoreFromTray() {
  RemoveTrayIcon();
  ::ShowWindow(GetHandle(), SW_RESTORE);
  ::SetForegroundWindow(GetHandle());
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) return;
  ::AppendMenuW(menu, MF_STRING, kTrayShowWindowCommand, L"Show Window");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kTrayExitCommand, L"Exit");

  POINT point;
  ::GetCursorPos(&point);
  ::SetForegroundWindow(GetHandle());
  ::TrackPopupMenu(
      menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN,
      point.x, point.y, 0, GetHandle(), nullptr);
  ::DestroyMenu(menu);
}
