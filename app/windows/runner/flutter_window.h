#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <chrono>
#include <cstdint>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static constexpr UINT_PTR kTrackingTimerId = 1;
  static constexpr UINT kTrayIconMessage = WM_APP + 1;
  static constexpr UINT kTrayIconId = 1;
  static constexpr UINT kTrayShowWindowCommand = 1001;
  static constexpr UINT kTrayExitCommand = 1002;

  void StartTrackingTitle(int64_t started_at, int64_t paused_seconds);
  void StopTrackingTitle();
  void UpdateTrackingTitle();
  void SetMinimizeToTray(bool enabled);
  void AddTrayIcon();
  void RemoveTrayIcon();
  void RestoreFromTray();
  void ShowTrayMenu();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> title_channel_;
  std::chrono::system_clock::time_point tracking_started_at_;
  int64_t tracking_paused_seconds_ = 0;
  bool minimize_to_tray_ = false;
  bool tray_icon_visible_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
