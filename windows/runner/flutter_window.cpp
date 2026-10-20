#include "flutter_window.h"

#include <dwmapi.h>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

static HHOOK g_mouse_hook = nullptr;
static FlutterWindow* g_current_window = nullptr;
static ULONGLONG g_last_action_time = 0;

namespace {

// window_manager uses the same per-window policy for transparent windows.
// It also provides a blur fallback without changing system-wide settings.
bool ApplyLegacyWindowAccent(HWND window, int state) {
  struct AccentPolicy {
    int state;
    int flags;
    int color;
    int animation;
  };
  struct CompositionAttributeData {
    int attribute;
    PVOID data;
    SIZE_T size;
  };
  using SetCompositionAttribute =
      BOOL(WINAPI*)(HWND, CompositionAttributeData*);
  const auto user32 = GetModuleHandleW(L"user32.dll");
  if (!user32) return false;
  const auto set_attribute = reinterpret_cast<SetCompositionAttribute>(
      GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (!set_attribute) {
    SetLastError(ERROR_PROC_NOT_FOUND);
    return false;
  }
  AccentPolicy policy = {state, 2, 0, 0};
  CompositionAttributeData data = {19, &policy, sizeof(policy)};
  SetLastError(ERROR_SUCCESS);
  return set_attribute(window, &data) != FALSE;
}

}  // namespace

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

enum TaskbarButtonId {
  kThbPrev = 1001,
  kThbPlayPause = 1002,
  kThbNext = 1003,
};

static HICON CreateMediaIcon(int type) {
  const int size = 16;
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = size;
  bmi.bmiHeader.biHeight = -size; // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  uint32_t* pixels = nullptr;
  HDC hdc = GetDC(nullptr);
  HBITMAP hColor = CreateDIBSection(hdc, &bmi, DIB_RGB_COLORS, reinterpret_cast<void**>(&pixels), nullptr, 0);
  HDC memDC = CreateCompatibleDC(hdc);
  HBITMAP oldBmp = static_cast<HBITMAP>(SelectObject(memDC, hColor));
  ReleaseDC(nullptr, hdc);

  if (!pixels) {
    DeleteDC(memDC);
    return nullptr;
  }

  memset(pixels, 0, size * size * sizeof(uint32_t));

  HBRUSH brush = CreateSolidBrush(RGB(255, 255, 255));
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(255, 255, 255));
  HBRUSH oldBrush = static_cast<HBRUSH>(SelectObject(memDC, brush));
  HPEN oldPen = static_cast<HPEN>(SelectObject(memDC, pen));

  if (type == 0) { // PREV
    RECT r = {3, 3, 5, 13};
    FillRect(memDC, &r, brush);
    POINT pts[3] = {{12, 3}, {5, 8}, {12, 13}};
    Polygon(memDC, pts, 3);
  } else if (type == 1) { // PLAY
    POINT pts[3] = {{5, 3}, {13, 8}, {5, 13}};
    Polygon(memDC, pts, 3);
  } else if (type == 2) { // PAUSE
    RECT r1 = {4, 3, 7, 13};
    RECT r2 = {9, 3, 12, 13};
    FillRect(memDC, &r1, brush);
    FillRect(memDC, &r2, brush);
  } else if (type == 3) { // NEXT
    POINT pts[3] = {{4, 3}, {11, 8}, {4, 13}};
    Polygon(memDC, pts, 3);
    RECT r = {11, 3, 13, 13};
    FillRect(memDC, &r, brush);
  }

  SelectObject(memDC, oldBrush);
  SelectObject(memDC, oldPen);
  DeleteObject(brush);
  DeleteObject(pen);
  SelectObject(memDC, oldBmp);
  DeleteDC(memDC);

  for (int i = 0; i < size * size; ++i) {
    if ((pixels[i] & 0x00FFFFFF) != 0) {
      pixels[i] |= 0xFF000000;
    }
  }

  HBITMAP hMono = CreateBitmap(size, size, 1, 1, nullptr);
  ICONINFO ii = {};
  ii.fIcon = TRUE;
  ii.hbmColor = hColor;
  ii.hbmMask = hMono;
  HICON icon = CreateIconIndirect(&ii);

  DeleteObject(hColor);
  DeleteObject(hMono);
  return icon;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::SendMouseHotkey(const std::string& action) {
  if (mouse_channel_) {
    mouse_channel_->InvokeMethod(action, nullptr);
  }
}

void FlutterWindow::InitTaskbarToolbar() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  if (!taskbar_list_) {
    CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                     IID_PPV_ARGS(&taskbar_list_));
    if (taskbar_list_) {
      taskbar_list_->HrInit();
    }
  }

  if (!taskbar_list_) return;

  if (!icon_prev_) icon_prev_ = CreateMediaIcon(0);
  if (!icon_play_) icon_play_ = CreateMediaIcon(1);
  if (!icon_pause_) icon_pause_ = CreateMediaIcon(2);
  if (!icon_next_) icon_next_ = CreateMediaIcon(3);

  THUMBBUTTON buttons[3] = {};

  // Button 0: Previous
  buttons[0].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  buttons[0].iId = kThbPrev;
  buttons[0].hIcon = icon_prev_;
  wcscpy_s(buttons[0].szTip, L"Anterior");
  buttons[0].dwFlags = THBF_ENABLED;

  // Button 1: Play/Pause
  buttons[1].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  buttons[1].iId = kThbPlayPause;
  buttons[1].hIcon = is_playing_ ? icon_pause_ : icon_play_;
  wcscpy_s(buttons[1].szTip, is_playing_ ? L"Pausar" : L"Reproducir");
  buttons[1].dwFlags = THBF_ENABLED;

  // Button 2: Next
  buttons[2].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  buttons[2].iId = kThbNext;
  buttons[2].hIcon = icon_next_;
  wcscpy_s(buttons[2].szTip, L"Siguiente");
  buttons[2].dwFlags = THBF_ENABLED;

  taskbar_list_->ThumbBarAddButtons(hwnd, 3, buttons);
}

void FlutterWindow::UpdateTaskbarPlayPause(bool is_playing) {
  is_playing_ = is_playing;
  HWND hwnd = GetHandle();
  if (!hwnd || !taskbar_list_) return;

  if (!icon_play_) icon_play_ = CreateMediaIcon(1);
  if (!icon_pause_) icon_pause_ = CreateMediaIcon(2);

  THUMBBUTTON btn = {};
  btn.dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  btn.iId = kThbPlayPause;
  btn.hIcon = is_playing ? icon_pause_ : icon_play_;
  wcscpy_s(btn.szTip, is_playing ? L"Pausar" : L"Reproducir");
  btn.dwFlags = THBF_ENABLED;

  taskbar_list_->ThumbBarUpdateButtons(hwnd, 1, &btn);
}

HRESULT FlutterWindow::ApplyWindowEffects(bool transparent, bool blur,
                                        bool dark) {
  const HWND window = GetHandle();
  if (!window) return HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE);

  const BOOL dark_mode = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(window, 20, &dark_mode, sizeof(dark_mode));

  // DWMWA_SYSTEMBACKDROP_TYPE (38) is supported from Windows 11 build 22621.
  // Value 3 is Desktop Acrylic, which blurs content behind this window;
  // value 1 disables the system backdrop. Numeric constants keep older SDKs
  // buildable while the HRESULT reports runtime support to Dart.
  DWORD transparency_enabled = 1;
  DWORD value_size = sizeof(transparency_enabled);
  const LSTATUS preference_result = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"EnableTransparency", RRF_RT_REG_DWORD, nullptr,
      &transparency_enabled, &value_size);
  const bool legacy_blur = transparent && blur &&
      preference_result == ERROR_SUCCESS && transparency_enabled == 0;
  const int backdrop = transparent && blur && !legacy_blur ? 3 : 1;
  if (transparent && blur && !legacy_blur &&
      !ApplyLegacyWindowAccent(window, 0)) {
    const DWORD error = GetLastError();
    return error == ERROR_SUCCESS ? E_FAIL : HRESULT_FROM_WIN32(error);
  }
  const HRESULT backdrop_result =
      DwmSetWindowAttribute(window, 38, &backdrop, sizeof(backdrop));
  if (FAILED(backdrop_result) && transparent && blur && !legacy_blur) {
    return backdrop_result;
  }
  // Desktop Acrylic falls back to an opaque fill when Windows transparency
  // is disabled. Use blur on this HWND alone, leaving that preference intact.
  if (legacy_blur && !ApplyLegacyWindowAccent(window, 3)) {
    const DWORD error = GetLastError();
    return error == ERROR_SUCCESS ? E_FAIL : HRESULT_FROM_WIN32(error);
  }

  // Windows 11 24H2 can explicitly preserve the alpha of redirected content.
  // Older Windows versions do not expose this optional attribute.
  const BOOL use_alpha = transparent ? TRUE : FALSE;
  DwmSetWindowAttribute(window, 39, &use_alpha, sizeof(use_alpha));
  const MARGINS margins = transparent ? MARGINS{-1, -1, -1, -1}
                                     : MARGINS{0, 0, 0, 0};
  const HRESULT frame_result = DwmExtendFrameIntoClientArea(window, &margins);
  if (FAILED(frame_result)) return frame_result;

  effects_transparent_ = transparent;
  effects_blur_ = blur;
  effects_dark_ = dark;
  return S_OK;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  mouse_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.crotowave/global_mouse_hotkeys",
          &flutter::StandardMethodCodec::GetInstance());

  mouse_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setPlaying") {
          if (const auto* val = std::get_if<bool>(call.arguments())) {
            UpdateTaskbarPlayPause(*val);
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  effects_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.crotowave/window_effects",
          &flutter::StandardMethodCodec::GetInstance());
  effects_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setEffects") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("invalid_arguments", "Expected window effect options.");
          return;
        }
        const auto transparent = args->find(flutter::EncodableValue("transparent"));
        const auto blur = args->find(flutter::EncodableValue("blur"));
        const auto dark = args->find(flutter::EncodableValue("dark"));
        if (transparent == args->end() || blur == args->end() ||
            dark == args->end() ||
            !std::holds_alternative<bool>(transparent->second) ||
            !std::holds_alternative<bool>(blur->second) ||
            !std::holds_alternative<bool>(dark->second)) {
          result->Error("invalid_arguments",
                        "transparent, blur and dark must be booleans.");
          return;
        }
        const HRESULT status = ApplyWindowEffects(
            std::get<bool>(transparent->second), std::get<bool>(blur->second),
            std::get<bool>(dark->second));
        if (FAILED(status)) {
          result->Error("window_effects_unavailable",
                        "Windows could not apply the desktop backdrop.",
                        flutter::EncodableValue(static_cast<int64_t>(status)));
          return;
        }
        result->Success();
      });

  g_current_window = this;
  g_mouse_hook = SetWindowsHookEx(
      WH_MOUSE_LL, LowLevelMouseProc, GetModuleHandle(nullptr), 0);

  taskbar_button_created_msg_ = ::RegisterWindowMessage(L"TaskbarButtonCreated");
  InitTaskbarToolbar();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (effects_channel_) {
    effects_channel_->SetMethodCallHandler(nullptr);
    effects_channel_ = nullptr;
  }
  if (taskbar_list_) {
    taskbar_list_->Release();
    taskbar_list_ = nullptr;
  }
  if (icon_prev_) { DestroyIcon(icon_prev_); icon_prev_ = nullptr; }
  if (icon_play_) { DestroyIcon(icon_play_); icon_play_ = nullptr; }
  if (icon_pause_) { DestroyIcon(icon_pause_); icon_pause_ = nullptr; }
  if (icon_next_) { DestroyIcon(icon_next_); icon_next_ = nullptr; }

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
  if (message == taskbar_button_created_msg_) {
    InitTaskbarToolbar();
    return 0;
  }

  if (message == WM_COMMAND) {
    UINT id = LOWORD(wparam);
    if (id == kThbPrev) {
      SendMouseHotkey("skipPrevious");
      return 0;
    } else if (id == kThbPlayPause) {
      SendMouseHotkey("togglePlayPause");
      return 0;
    } else if (id == kThbNext) {
      SendMouseHotkey("skipNext");
      return 0;
    }
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
    case WM_DWMCOMPOSITIONCHANGED:
      ApplyWindowEffects(effects_transparent_, effects_blur_, effects_dark_);
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
