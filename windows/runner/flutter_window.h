#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <atomic>
#include <memory>
#include <string>
#include <thread>
#include <shobjidl.h>
#include <shellapi.h>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  void SendMouseHotkey(const std::string& action);
  void UpdateTaskbarPlayPause(bool is_playing);
  void HideToTray();
  void RestoreFromTray();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void InitTaskbarToolbar();
  void InitTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayContextMenu();
  void StartHookThread();
  void StopHookThread();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Channel to notify Flutter about global mouse hotkeys and taskbar events.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> mouse_channel_;

  ITaskbarList3* taskbar_list_ = nullptr;
  UINT taskbar_button_created_msg_ = 0;
  bool is_playing_ = false;
  HICON icon_prev_ = nullptr;
  HICON icon_play_ = nullptr;
  HICON icon_pause_ = nullptr;
  HICON icon_next_ = nullptr;

  NOTIFYICONDATAW nid_ = {};
  bool tray_icon_added_ = false;
  bool tray_balloon_shown_ = false;
  bool force_quit_ = false;

  std::thread hook_thread_;
  DWORD hook_thread_id_ = 0;
  std::atomic<bool> hook_thread_running_{false};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
