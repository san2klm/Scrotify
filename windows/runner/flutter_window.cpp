#include "flutter_window.h"

#include <mutex>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kWmCrotoWaveHotkey = WM_USER + 200;
constexpr UINT kWmTrayIcon = WM_USER + 201;
constexpr UINT kWmRestoreFromTray = WM_USER + 202;
constexpr UINT kWmCrotoWaveCaptured = WM_USER + 203;

enum HotkeyAction : WPARAM {
  kActionTogglePlayPause = 1,
  kActionSkipNext = 2,
  kActionSkipPrevious = 3,
  kActionVolumeUp = 4,
  kActionVolumeDown = 5,
};

enum TrayMenuId : UINT {
  kTrayOpen = 2001,
  kTrayPlayPause = 2002,
  kTrayNext = 2003,
  kTrayPrev = 2004,
  kTrayQuit = 2005,
};

enum TaskbarButtonId {
  kThbPrev = 1001,
  kThbPlayPause = 1002,
  kThbNext = 1003,
};

static HHOOK g_mouse_hook = nullptr;
static HHOOK g_keyboard_hook = nullptr;
static HWND g_main_hwnd = nullptr;

static std::atomic<bool> g_mouse_enabled{true};
static std::atomic<bool> g_capturing_shortcut{false};
static std::atomic<bool> g_mouse_global{true};
static std::atomic<bool> g_mouse_middle_enabled{true};
static std::atomic<bool> g_close_to_tray{true};

static std::mutex g_captured_mutex;
static std::string g_captured_binding;

// 1 = mouse_xb1, 2 = mouse_xb2, 3 = mouse_middle, 4 = mouse_right, 0 = none/key
static std::atomic<int> g_play_pause_mouse_btn{1};
static std::atomic<int> g_next_track_mouse_btn{2};
static std::atomic<DWORD> g_play_pause_vk{0};
static std::atomic<DWORD> g_next_track_vk{0};

static std::atomic<ULONGLONG> g_last_xbutton1_time{0};
static std::atomic<ULONGLONG> g_last_xbutton2_time{0};
static std::atomic<ULONGLONG> g_last_mbutton_time{0};
static std::atomic<ULONGLONG> g_last_rbutton_time{0};
static std::atomic<ULONGLONG> g_last_key_play_time{0};
static std::atomic<ULONGLONG> g_last_key_next_time{0};
static std::atomic<ULONGLONG> g_last_hook_event_time{0};

static DWORD NormalizeVkCode(DWORD vk) {
  if (vk == VK_LSHIFT || vk == VK_RSHIFT) return VK_SHIFT;
  if (vk == VK_LCONTROL || vk == VK_RCONTROL) return VK_CONTROL;
  if (vk == VK_LMENU || vk == VK_RMENU) return VK_MENU;
  return vk;
}

static std::string VkCodeToLabel(DWORD vk, DWORD scanCode, DWORD flags) {
  vk = NormalizeVkCode(vk);
  if (vk >= 0x41 && vk <= 0x5A) {
    return std::string(1, static_cast<char>(vk));
  }
  if (vk >= 0x30 && vk <= 0x39) {
    return std::string(1, static_cast<char>(vk));
  }
  if (vk >= VK_F1 && vk <= VK_F24) {
    return "F" + std::to_string(vk - VK_F1 + 1);
  }
  if (vk >= VK_NUMPAD0 && vk <= VK_NUMPAD9) {
    return "Num " + std::to_string(vk - VK_NUMPAD0);
  }
  switch (vk) {
    case VK_SPACE: return "Espacio";
    case VK_RETURN: return "Enter";
    case VK_TAB: return "Tab";
    case VK_BACK: return "Borrar";
    case VK_CAPITAL: return "Bloq Mayús";
    case VK_SHIFT: return "Shift";
    case VK_CONTROL: return "Ctrl";
    case VK_MENU: return "Alt";
    case VK_INSERT: return "Insert";
    case VK_DELETE: return "Supr";
    case VK_HOME: return "Inicio";
    case VK_END: return "Fin";
    case VK_PRIOR: return "Re Pág";
    case VK_NEXT: return "Av Pág";
    case VK_UP: return "Flecha Arriba";
    case VK_DOWN: return "Flecha Abajo";
    case VK_LEFT: return "Flecha Izquierda";
    case VK_RIGHT: return "Flecha Derecha";
    case VK_ADD: return "Num +";
    case VK_SUBTRACT: return "Num -";
    case VK_MULTIPLY: return "Num *";
    case VK_DIVIDE: return "Num /";
    case VK_DECIMAL: return "Num .";
    case VK_MEDIA_PLAY_PAUSE: return "Media Play/Pausa";
    case VK_MEDIA_NEXT_TRACK: return "Media Siguiente";
    case VK_MEDIA_PREV_TRACK: return "Media Anterior";
    case VK_MEDIA_STOP: return "Media Stop";
    case VK_PAUSE: return "Pausa";
    case VK_SCROLL: return "Bloq Despl";
  }
  LONG lparam_name = (scanCode << 16);
  if (flags & LLKHF_EXTENDED) {
    lparam_name |= (1 << 24);
  }
  wchar_t wname[64] = {};
  if (GetKeyNameTextW(lparam_name, wname, 63) > 0) {
    int needed = WideCharToMultiByte(CP_UTF8, 0, wname, -1, nullptr, 0, nullptr, nullptr);
    if (needed > 1) {
      std::string out(needed - 1, '\0');
      WideCharToMultiByte(CP_UTF8, 0, wname, -1, out.data(), needed, nullptr, nullptr);
      return out;
    }
  }
  return "VK " + std::to_string(vk);
}

static void DispatchCapturedShortcut(const std::string& raw) {
  {
    std::lock_guard<std::mutex> lock(g_captured_mutex);
    g_captured_binding = raw;
  }
  HWND hwnd = g_main_hwnd;
  if (hwnd) {
    PostMessageW(hwnd, kWmCrotoWaveCaptured, 0, 0);
  }
}

static bool IsPointOverCrotoWave(POINT pt) {
  HWND hwnd = g_main_hwnd;
  if (!hwnd || !IsWindowVisible(hwnd) || IsIconic(hwnd)) {
    return false;
  }
  HWND target = WindowFromPoint(pt);
  if (!target) return false;
  HWND root = GetAncestor(target, GA_ROOT);
  return (target == hwnd || root == hwnd || IsChild(hwnd, target));
}

static bool IsPointOverWebBrowser(POINT pt) {
  HWND target = WindowFromPoint(pt);
  if (!target) return false;
  HWND root = GetAncestor(target, GA_ROOT);
  if (!root) root = target;
  wchar_t class_name[128] = {};
  if (GetClassNameW(root, class_name, 127) > 0) {
    if (wcscmp(class_name, L"Chrome_WidgetWin_1") == 0 ||
        wcscmp(class_name, L"MozillaWindowClass") == 0) {
      if (root != g_main_hwnd) {
        return true;
      }
    }
  }
  return false;
}

static void DispatchHotkeyToMain(HotkeyAction action) {
  HWND hwnd = g_main_hwnd;
  if (hwnd) {
    PostMessageW(hwnd, kWmCrotoWaveHotkey, static_cast<WPARAM>(action), 0);
  }
}

static bool HandleConfiguredSideButton(int btn_id, ULONGLONG now,
                                       std::atomic<ULONGLONG>& last_time) {
  int pp_btn = g_play_pause_mouse_btn.load(std::memory_order_relaxed);
  int nt_btn = g_next_track_mouse_btn.load(std::memory_order_relaxed);
  if (pp_btn == btn_id) {
    ULONGLONG last = last_time.load(std::memory_order_relaxed);
    if (now - last < 380) {
      last_time.store(0, std::memory_order_relaxed);
      DispatchHotkeyToMain(kActionSkipPrevious);
    } else {
      last_time.store(now, std::memory_order_relaxed);
      DispatchHotkeyToMain(kActionTogglePlayPause);
    }
    return true;
  }
  if (nt_btn == btn_id) {
    ULONGLONG last = last_time.load(std::memory_order_relaxed);
    if (now - last >= 220) {
      last_time.store(now, std::memory_order_relaxed);
      DispatchHotkeyToMain(kActionSkipNext);
    }
    return true;
  }
  return false;
}

static LRESULT CALLBACK LowLevelMouseProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode < 0 || wParam == WM_MOUSEMOVE) {
    return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
  }

  MSLLHOOKSTRUCT* pMouse = reinterpret_cast<MSLLHOOKSTRUCT*>(lParam);
  if (!pMouse || g_main_hwnd == nullptr) {
    return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
  }

  // Modo captura ("Seleccionar botón a usar"): detecta cualquier botón del mouse (excepto clic izquierdo)
  if (g_capturing_shortcut.load(std::memory_order_relaxed)) {
    WORD xbutton = HIWORD(pMouse->mouseData);
    if (wParam == WM_XBUTTONDOWN || wParam == WM_NCXBUTTONDOWN) {
      if (xbutton == XBUTTON1) {
        g_capturing_shortcut.store(false, std::memory_order_relaxed);
        DispatchCapturedShortcut("mouse:xbutton1");
        return 1;
      } else if (xbutton == XBUTTON2) {
        g_capturing_shortcut.store(false, std::memory_order_relaxed);
        DispatchCapturedShortcut("mouse:xbutton2");
        return 1;
      }
    } else if (wParam == WM_MBUTTONDOWN) {
      g_capturing_shortcut.store(false, std::memory_order_relaxed);
      DispatchCapturedShortcut("mouse:middle");
      return 1;
    } else if (wParam == WM_RBUTTONDOWN) {
      g_capturing_shortcut.store(false, std::memory_order_relaxed);
      DispatchCapturedShortcut("mouse:right");
      return 1;
    }
    return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
  }

  if (!g_mouse_enabled.load(std::memory_order_relaxed)) {
    return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
  }

  if (wParam != WM_XBUTTONDOWN && wParam != WM_NCXBUTTONDOWN &&
      wParam != WM_XBUTTONUP && wParam != WM_NCXBUTTONUP &&
      wParam != WM_MBUTTONDOWN && wParam != WM_MBUTTONUP &&
      wParam != WM_RBUTTONDOWN && wParam != WM_RBUTTONUP &&
      wParam != WM_MOUSEWHEEL) {
    return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
  }

  bool global_allowed = g_mouse_global.load(std::memory_order_relaxed);
  bool is_over_crotowave = IsPointOverCrotoWave(pMouse->pt);

  ULONGLONG now = GetTickCount64();
  g_last_hook_event_time.store(now, std::memory_order_relaxed);

  if (!global_allowed && !is_over_crotowave) {
    return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
  }

  if (!is_over_crotowave) {
    WORD xbutton = HIWORD(pMouse->mouseData);

    if (wParam == WM_XBUTTONDOWN || wParam == WM_NCXBUTTONDOWN) {
      if (xbutton == XBUTTON1) {
        if (HandleConfiguredSideButton(1, now, g_last_xbutton1_time)) {
          return 1;
        }
      } else if (xbutton == XBUTTON2) {
        if (HandleConfiguredSideButton(2, now, g_last_xbutton2_time)) {
          return 1;
        }
      }
    } else if (wParam == WM_XBUTTONUP || wParam == WM_NCXBUTTONUP) {
      int pp_btn = g_play_pause_mouse_btn.load(std::memory_order_relaxed);
      int nt_btn = g_next_track_mouse_btn.load(std::memory_order_relaxed);
      if (xbutton == XBUTTON1 && (pp_btn == 1 || nt_btn == 1)) {
        return 1;
      }
      if (xbutton == XBUTTON2 && (pp_btn == 2 || nt_btn == 2)) {
        return 1;
      }
    } else if (wParam == WM_RBUTTONDOWN) {
      HandleConfiguredSideButton(4, now, g_last_rbutton_time);
    } else if (wParam == WM_MBUTTONDOWN) {
      int pp_btn = g_play_pause_mouse_btn.load(std::memory_order_relaxed);
      int nt_btn = g_next_track_mouse_btn.load(std::memory_order_relaxed);
      bool mid_toggle = g_mouse_middle_enabled.load(std::memory_order_relaxed);
      if (pp_btn == 3 || nt_btn == 3 || mid_toggle) {
        HotkeyAction mid_action =
            (nt_btn == 3 && pp_btn != 3) ? kActionSkipNext : kActionTogglePlayPause;
        bool in_browser = IsPointOverWebBrowser(pMouse->pt);
        bool alt_held = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
        ULONGLONG last = g_last_mbutton_time.load(std::memory_order_relaxed);

        if (!in_browser || alt_held) {
          if (now - last >= 220) {
            g_last_mbutton_time.store(now, std::memory_order_relaxed);
            DispatchHotkeyToMain(mid_action);
          }
          if (alt_held) return 1;
        } else {
          if (now - last < 360) {
            g_last_mbutton_time.store(0, std::memory_order_relaxed);
            DispatchHotkeyToMain(mid_action);
            return 1;
          } else {
            g_last_mbutton_time.store(now, std::memory_order_relaxed);
          }
        }
      }
    } else if (wParam == WM_MOUSEWHEEL) {
      bool alt_held = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
      if (alt_held) {
        short delta = static_cast<short>(HIWORD(pMouse->mouseData));
        if (delta > 0) {
          DispatchHotkeyToMain(kActionVolumeUp);
          return 1;
        } else if (delta < 0) {
          DispatchHotkeyToMain(kActionVolumeDown);
          return 1;
        }
      }
    }
  }

  return CallNextHookEx(g_mouse_hook, nCode, wParam, lParam);
}

static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode >= 0 && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
    KBDLLHOOKSTRUCT* pKey = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
    if (pKey && g_main_hwnd != nullptr) {
      // Modo captura ("Seleccionar botón a usar"): detecta cualquier tecla presionada
      if (g_capturing_shortcut.load(std::memory_order_relaxed)) {
        if (pKey->vkCode == VK_ESCAPE) {
          g_capturing_shortcut.store(false, std::memory_order_relaxed);
          DispatchCapturedShortcut("cancel");
          return 1;
        }
        if (pKey->vkCode != VK_LWIN && pKey->vkCode != VK_RWIN) {
          DWORD norm_vk = NormalizeVkCode(pKey->vkCode);
          std::string label = VkCodeToLabel(norm_vk, pKey->scanCode, pKey->flags);
          std::string raw = "key:" + std::to_string(norm_vk) + ":0:" + label;
          g_capturing_shortcut.store(false, std::memory_order_relaxed);
          DispatchCapturedShortcut(raw);
          return 1;
        }
      }

      if (g_mouse_enabled.load(std::memory_order_relaxed)) {
        DWORD norm_vk = NormalizeVkCode(pKey->vkCode);
        if (GetForegroundWindow() != g_main_hwnd) {
          if (norm_vk == VK_MEDIA_PLAY_PAUSE) {
            DispatchHotkeyToMain(kActionTogglePlayPause);
          } else if (norm_vk == VK_MEDIA_NEXT_TRACK) {
            DispatchHotkeyToMain(kActionSkipNext);
          } else if (norm_vk == VK_MEDIA_PREV_TRACK) {
            DispatchHotkeyToMain(kActionSkipPrevious);
          } else if (g_mouse_global.load(std::memory_order_relaxed)) {
            ULONGLONG now = GetTickCount64();
            DWORD pp_vk = g_play_pause_vk.load(std::memory_order_relaxed);
            DWORD nt_vk = g_next_track_vk.load(std::memory_order_relaxed);
            if (pp_vk != 0 && norm_vk == pp_vk) {
              ULONGLONG last = g_last_key_play_time.load(std::memory_order_relaxed);
              if (now - last >= 220) {
                g_last_key_play_time.store(now, std::memory_order_relaxed);
                DispatchHotkeyToMain(kActionTogglePlayPause);
              }
            } else if (nt_vk != 0 && norm_vk == nt_vk) {
              ULONGLONG last = g_last_key_next_time.load(std::memory_order_relaxed);
              if (now - last >= 220) {
                g_last_key_next_time.store(now, std::memory_order_relaxed);
                DispatchHotkeyToMain(kActionSkipNext);
              }
            }
          }
        }
      }
    }
  }
  return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
}

}  // namespace

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

FlutterWindow::~FlutterWindow() {
  StopHookThread();
  RemoveTrayIcon();
}

void FlutterWindow::SendMouseHotkey(const std::string& action) {
  if (mouse_channel_) {
    mouse_channel_->InvokeMethod(action, nullptr);
    if (flutter_controller_) {
      flutter_controller_->ForceRedraw();
    }
  }
}

void FlutterWindow::StartHookThread() {
  if (hook_thread_running_.load()) return;
  hook_thread_running_.store(true);

  hook_thread_ = std::thread([this]() {
    hook_thread_id_ = GetCurrentThreadId();

    MSG msg;
    PeekMessageW(&msg, nullptr, WM_USER, WM_USER, PM_NOREMOVE);

    HINSTANCE hMod = GetModuleHandleW(nullptr);
    g_mouse_hook = SetWindowsHookExW(WH_MOUSE_LL, LowLevelMouseProc, hMod, 0);
    g_keyboard_hook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, hMod, 0);

    UINT_PTR timer_id = SetTimer(nullptr, 1, 25, nullptr);

    bool prev_xb1 = false;
    bool prev_xb2 = false;
    bool prev_mb = false;
    bool prev_rb = false;
    bool prev_pp_key = false;
    bool prev_nt_key = false;

    while (hook_thread_running_.load(std::memory_order_relaxed)) {
      BOOL ret = GetMessageW(&msg, nullptr, 0, 0);
      if (ret <= 0) break;

      if (msg.message == WM_QUIT) {
        break;
      }

      if (msg.message == WM_TIMER) {
        bool xb1_down = (GetAsyncKeyState(VK_XBUTTON1) & 0x8000) != 0;
        bool xb2_down = (GetAsyncKeyState(VK_XBUTTON2) & 0x8000) != 0;
        bool mb_down = (GetAsyncKeyState(VK_MBUTTON) & 0x8000) != 0;
        bool rb_down = (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0;
        DWORD pp_vk = g_play_pause_vk.load(std::memory_order_relaxed);
        DWORD nt_vk = g_next_track_vk.load(std::memory_order_relaxed);
        bool pp_key_down = (pp_vk != 0) && ((GetAsyncKeyState(static_cast<int>(pp_vk)) & 0x8000) != 0);
        bool nt_key_down = (nt_vk != 0) && ((GetAsyncKeyState(static_cast<int>(nt_vk)) & 0x8000) != 0);

        if (g_capturing_shortcut.load(std::memory_order_relaxed)) {
          if (xb1_down && !prev_xb1) {
            g_capturing_shortcut.store(false, std::memory_order_relaxed);
            DispatchCapturedShortcut("mouse:xbutton1");
          } else if (xb2_down && !prev_xb2) {
            g_capturing_shortcut.store(false, std::memory_order_relaxed);
            DispatchCapturedShortcut("mouse:xbutton2");
          } else if (mb_down && !prev_mb) {
            g_capturing_shortcut.store(false, std::memory_order_relaxed);
            DispatchCapturedShortcut("mouse:middle");
          } else if (rb_down && !prev_rb) {
            g_capturing_shortcut.store(false, std::memory_order_relaxed);
            DispatchCapturedShortcut("mouse:right");
          }
        } else if (g_mouse_enabled.load(std::memory_order_relaxed) &&
                   g_mouse_global.load(std::memory_order_relaxed)) {
          ULONGLONG now = GetTickCount64();
          ULONGLONG last_hook = g_last_hook_event_time.load(std::memory_order_relaxed);

          if (now - last_hook > 90) {
            POINT pt = {};
            GetCursorPos(&pt);
            if (!IsPointOverCrotoWave(pt)) {
              if (xb1_down && !prev_xb1) {
                HandleConfiguredSideButton(1, now, g_last_xbutton1_time);
              }
              if (xb2_down && !prev_xb2) {
                HandleConfiguredSideButton(2, now, g_last_xbutton2_time);
              }
              if (rb_down && !prev_rb) {
                HandleConfiguredSideButton(4, now, g_last_rbutton_time);
              }
              int pp_btn = g_play_pause_mouse_btn.load(std::memory_order_relaxed);
              int nt_btn = g_next_track_mouse_btn.load(std::memory_order_relaxed);
              bool mid_toggle = g_mouse_middle_enabled.load(std::memory_order_relaxed);
              if (mb_down && !prev_mb && (pp_btn == 3 || nt_btn == 3 || mid_toggle)) {
                if (!IsPointOverWebBrowser(pt)) {
                  ULONGLONG last = g_last_mbutton_time.load(std::memory_order_relaxed);
                  if (now - last >= 220) {
                    g_last_mbutton_time.store(now, std::memory_order_relaxed);
                    HotkeyAction mid_action =
                        (nt_btn == 3 && pp_btn != 3) ? kActionSkipNext : kActionTogglePlayPause;
                    DispatchHotkeyToMain(mid_action);
                  }
                }
              }
              if (pp_key_down && !prev_pp_key && GetForegroundWindow() != g_main_hwnd) {
                ULONGLONG last = g_last_key_play_time.load(std::memory_order_relaxed);
                if (now - last >= 220) {
                  g_last_key_play_time.store(now, std::memory_order_relaxed);
                  DispatchHotkeyToMain(kActionTogglePlayPause);
                }
              }
              if (nt_key_down && !prev_nt_key && GetForegroundWindow() != g_main_hwnd) {
                ULONGLONG last = g_last_key_next_time.load(std::memory_order_relaxed);
                if (now - last >= 220) {
                  g_last_key_next_time.store(now, std::memory_order_relaxed);
                  DispatchHotkeyToMain(kActionSkipNext);
                }
              }
            }
          }
        }

        prev_xb1 = xb1_down;
        prev_xb2 = xb2_down;
        prev_mb = mb_down;
        prev_rb = rb_down;
        prev_pp_key = pp_key_down;
        prev_nt_key = nt_key_down;
        continue;
      }

      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }

    if (timer_id) {
      KillTimer(nullptr, timer_id);
    }
    if (g_mouse_hook) {
      UnhookWindowsHookEx(g_mouse_hook);
      g_mouse_hook = nullptr;
    }
    if (g_keyboard_hook) {
      UnhookWindowsHookEx(g_keyboard_hook);
      g_keyboard_hook = nullptr;
    }
  });
}

void FlutterWindow::StopHookThread() {
  if (!hook_thread_running_.exchange(false)) return;
  if (hook_thread_id_ != 0) {
    PostThreadMessageW(hook_thread_id_, WM_QUIT, 0, 0);
  }
  if (hook_thread_.joinable()) {
    hook_thread_.join();
  }
  hook_thread_id_ = 0;
}

void FlutterWindow::InitTrayIcon() {
  HWND hwnd = GetHandle();
  if (!hwnd || tray_icon_added_) return;

  ZeroMemory(&nid_, sizeof(nid_));
  nid_.cbSize = sizeof(NOTIFYICONDATAW);
  nid_.hWnd = hwnd;
  nid_.uID = 1;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid_.uCallbackMessage = kWmTrayIcon;
  nid_.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(nid_.szTip, L"CrotoWave (Reproductor en segundo plano)");

  if (Shell_NotifyIconW(NIM_ADD, &nid_)) {
    tray_icon_added_ = true;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_icon_added_) {
    Shell_NotifyIconW(NIM_DELETE, &nid_);
    tray_icon_added_ = false;
  }
}

void FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  InitTrayIcon();
  ShowWindow(hwnd, SW_HIDE);

  if (tray_icon_added_ && !tray_balloon_shown_) {
    tray_balloon_shown_ = true;
    nid_.uFlags = NIF_INFO;
    wcscpy_s(nid_.szInfoTitle, L"CrotoWave sigue en segundo plano");
    wcscpy_s(nid_.szInfo,
             L"Podés seguir cambiando canciones y pausando con el mouse. Tocá el icono en la bandeja para abrirlo.");
    nid_.dwInfoFlags = NIIF_INFO;
    Shell_NotifyIconW(NIM_MODIFY, &nid_);
  }
}

void FlutterWindow::RestoreFromTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  ShowWindow(hwnd, SW_SHOW);
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetForegroundWindow(hwnd);
  SetFocus(hwnd);
  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }
}

void FlutterWindow::ShowTrayContextMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  HMENU menu = CreatePopupMenu();
  if (!menu) return;

  AppendMenuW(menu, MF_STRING, kTrayOpen, L"Abrir CrotoWave");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayPlayPause,
              is_playing_ ? L"Pausar reproducción" : L"Reproducir");
  AppendMenuW(menu, MF_STRING, kTrayNext, L"Siguiente canción");
  AppendMenuW(menu, MF_STRING, kTrayPrev, L"Canción anterior");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayQuit, L"Cerrar CrotoWave por completo");

  SetMenuDefaultItem(menu, kTrayOpen, FALSE);

  POINT pt = {};
  GetCursorPos(&pt);
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.x, pt.y, 0, hwnd, nullptr);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
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

  buttons[0].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  buttons[0].iId = kThbPrev;
  buttons[0].hIcon = icon_prev_;
  wcscpy_s(buttons[0].szTip, L"Anterior");
  buttons[0].dwFlags = THBF_ENABLED;

  buttons[1].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  buttons[1].iId = kThbPlayPause;
  buttons[1].hIcon = is_playing_ ? icon_pause_ : icon_play_;
  wcscpy_s(buttons[1].szTip, is_playing_ ? L"Pausar" : L"Reproducir");
  buttons[1].dwFlags = THBF_ENABLED;

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
        } else if (call.method_name() == "setMouseConfig") {
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it_en = args->find(flutter::EncodableValue("enabled"));
            if (it_en != args->end() && std::holds_alternative<bool>(it_en->second)) {
              g_mouse_enabled.store(std::get<bool>(it_en->second), std::memory_order_relaxed);
            }
            auto it_cap = args->find(flutter::EncodableValue("capturing"));
            if (it_cap != args->end() && std::holds_alternative<bool>(it_cap->second)) {
              g_capturing_shortcut.store(std::get<bool>(it_cap->second), std::memory_order_relaxed);
            }
            auto it_gl = args->find(flutter::EncodableValue("global"));
            if (it_gl != args->end() && std::holds_alternative<bool>(it_gl->second)) {
              g_mouse_global.store(std::get<bool>(it_gl->second), std::memory_order_relaxed);
            }
            auto it_mid = args->find(flutter::EncodableValue("middleClick"));
            if (it_mid != args->end() && std::holds_alternative<bool>(it_mid->second)) {
              g_mouse_middle_enabled.store(std::get<bool>(it_mid->second), std::memory_order_relaxed);
            }
            auto it_tray = args->find(flutter::EncodableValue("closeToTray"));
            if (it_tray != args->end() && std::holds_alternative<bool>(it_tray->second)) {
              g_close_to_tray.store(std::get<bool>(it_tray->second), std::memory_order_relaxed);
            }
            auto parse_btn_type = [](const std::string& t) -> int {
              if (t == "mouse_xb1") return 1;
              if (t == "mouse_xb2") return 2;
              if (t == "mouse_middle") return 3;
              if (t == "mouse_right") return 4;
              return 0;
            };
            auto it_ppt = args->find(flutter::EncodableValue("playPauseType"));
            if (it_ppt != args->end() && std::holds_alternative<std::string>(it_ppt->second)) {
              g_play_pause_mouse_btn.store(parse_btn_type(std::get<std::string>(it_ppt->second)),
                                           std::memory_order_relaxed);
            }
            auto it_ppvk = args->find(flutter::EncodableValue("playPauseVk"));
            if (it_ppvk != args->end() && std::holds_alternative<int32_t>(it_ppvk->second)) {
              g_play_pause_vk.store(static_cast<DWORD>(std::get<int32_t>(it_ppvk->second)),
                                    std::memory_order_relaxed);
            } else if (it_ppvk != args->end() && std::holds_alternative<int64_t>(it_ppvk->second)) {
              g_play_pause_vk.store(static_cast<DWORD>(std::get<int64_t>(it_ppvk->second)),
                                    std::memory_order_relaxed);
            }
            auto it_ntt = args->find(flutter::EncodableValue("nextTrackType"));
            if (it_ntt != args->end() && std::holds_alternative<std::string>(it_ntt->second)) {
              g_next_track_mouse_btn.store(parse_btn_type(std::get<std::string>(it_ntt->second)),
                                           std::memory_order_relaxed);
            }
            auto it_ntvk = args->find(flutter::EncodableValue("nextTrackVk"));
            if (it_ntvk != args->end() && std::holds_alternative<int32_t>(it_ntvk->second)) {
              g_next_track_vk.store(static_cast<DWORD>(std::get<int32_t>(it_ntvk->second)),
                                    std::memory_order_relaxed);
            } else if (it_ntvk != args->end() && std::holds_alternative<int64_t>(it_ntvk->second)) {
              g_next_track_vk.store(static_cast<DWORD>(std::get<int64_t>(it_ntvk->second)),
                                    std::memory_order_relaxed);
            }
          }
          result->Success();
        } else if (call.method_name() == "hideToTray") {
          HideToTray();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  g_main_hwnd = GetHandle();
  InitTrayIcon();
  StartHookThread();

  taskbar_button_created_msg_ = ::RegisterWindowMessageW(L"TaskbarButtonCreated");
  InitTaskbarToolbar();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  StopHookThread();
  RemoveTrayIcon();

  if (taskbar_list_) {
    taskbar_list_->Release();
    taskbar_list_ = nullptr;
  }
  if (icon_prev_) { DestroyIcon(icon_prev_); icon_prev_ = nullptr; }
  if (icon_play_) { DestroyIcon(icon_play_); icon_play_ = nullptr; }
  if (icon_pause_) { DestroyIcon(icon_pause_); icon_pause_ = nullptr; }
  if (icon_next_) { DestroyIcon(icon_next_); icon_next_ = nullptr; }

  if (g_main_hwnd == GetHandle()) {
    g_main_hwnd = nullptr;
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
  if (message == taskbar_button_created_msg_ && taskbar_button_created_msg_ != 0) {
    InitTaskbarToolbar();
    InitTrayIcon();
    return 0;
  }

  if (message == kWmRestoreFromTray) {
    RestoreFromTray();
    return 0;
  }

  if (message == kWmCrotoWaveCaptured) {
    std::string captured;
    {
      std::lock_guard<std::mutex> lock(g_captured_mutex);
      captured = g_captured_binding;
    }
    if (mouse_channel_ && !captured.empty()) {
      mouse_channel_->InvokeMethod(
          "onShortcutCaptured",
          std::make_unique<flutter::EncodableValue>(captured));
      if (flutter_controller_) {
        flutter_controller_->ForceRedraw();
      }
    }
    return 0;
  }

  if (message == kWmCrotoWaveHotkey) {
    switch (static_cast<HotkeyAction>(wparam)) {
      case kActionTogglePlayPause:
        SendMouseHotkey("togglePlayPause");
        break;
      case kActionSkipNext:
        SendMouseHotkey("skipNext");
        break;
      case kActionSkipPrevious:
        SendMouseHotkey("skipPrevious");
        break;
      case kActionVolumeUp:
        SendMouseHotkey("volumeUp");
        break;
      case kActionVolumeDown:
        SendMouseHotkey("volumeDown");
        break;
    }
    return 0;
  }

  if (message == kWmTrayIcon) {
    UINT event = LOWORD(lparam);
    if (event == WM_LBUTTONUP || event == WM_LBUTTONDBLCLK || event == NIN_BALLOONUSERCLICK) {
      RestoreFromTray();
    } else if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
      ShowTrayContextMenu();
    }
    return 0;
  }

  if (message == WM_CLOSE && !force_quit_ &&
      g_close_to_tray.load(std::memory_order_relaxed)) {
    HideToTray();
    return 0;
  }

  if (message == WM_COMMAND) {
    UINT id = LOWORD(wparam);
    if (id == kThbPrev || id == kTrayPrev) {
      SendMouseHotkey("skipPrevious");
      return 0;
    } else if (id == kThbPlayPause || id == kTrayPlayPause) {
      SendMouseHotkey("togglePlayPause");
      return 0;
    } else if (id == kThbNext || id == kTrayNext) {
      SendMouseHotkey("skipNext");
      return 0;
    } else if (id == kTrayOpen) {
      RestoreFromTray();
      return 0;
    } else if (id == kTrayQuit) {
      force_quit_ = true;
      RemoveTrayIcon();
      DestroyWindow(hwnd);
      return 0;
    }
  }

  if ((message == WM_SIZE && wparam == SIZE_MINIMIZED) ||
      (message == WM_SHOWWINDOW && wparam == FALSE)) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

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
