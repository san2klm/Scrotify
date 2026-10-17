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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
