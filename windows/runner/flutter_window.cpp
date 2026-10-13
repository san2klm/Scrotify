#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

static HHOOK g_mouse_hook = nullptr;
static FlutterWindow* g_current_window = nullptr;
static ULONGLONG g_last_action_time = 0;

static LRESULT CALLBACK LowLevelMouseProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode >= 0 && g_current_window != nullptr) {
    MSLLHOOKSTRUCT* pMouse = reinterpret_cast<MSLLHOOKSTRUCT*>(lParam);
    if (pMouse != nullptr) {
      WORD xbutton = HIWORD(pMouse->mouseData);
      if (wParam == WM_XBUTTONDOWN || wParam == WM_NCXBUTTONDOWN) {
        if (xbutton == XBUTTON1) {
          ULONGLONG now = GetTickCount64();
          if (now - g_last_action_time >= 250) {
            g_last_action_time = now;
            g_current_window->SendMouseHotkey("togglePlayPause");
          }
          return 1;
        } else if (xbutton == XBUTTON2) {
          ULONGLONG now = GetTickCount64();
          if (now - g_last_action_time >= 250) {
            g_last_action_time = now;
            g_current_window->SendMouseHotkey("skipNext");
          }
          return 1;
        }
      } else if (wParam == WM_XBUTTONUP || wParam == WM_NCXBUTTONUP) {
        if (xbutton == XBUTTON1 || xbutton == XBUTTON2) {
          return 1;
        }
      }
    }
  }
  return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::SendMouseHotkey(const std::string& action) {
  if (mouse_channel_) {
    mouse_channel_->InvokeMethod(action, nullptr);
  }
}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  mouse_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.scrotify/global_mouse_hotkeys",
          &flutter::StandardMethodCodec::GetInstance());

  g_current_window = this;
  g_mouse_hook = SetWindowsHookEx(
      WH_MOUSE_LL, LowLevelMouseProc, GetModuleHandle(nullptr), 0);

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
  if (g_mouse_hook != nullptr) {
    UnhookWindowsHookEx(g_mouse_hook);
    g_mouse_hook = nullptr;
  }
  if (g_current_window == this) {
    g_current_window = nullptr;
  }
  mouse_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
