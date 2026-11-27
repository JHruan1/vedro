#include "vedro_hardware_plugin.h"

#include <dwmapi.h>
#include <dxgi1_6.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <ks.h>
#include <ksmedia.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <cstdint>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

extern void VedroSetWin32FullscreenFlag(bool is_fullscreen);
extern void VedroApplyWin32WindowChrome(HWND const window,
                                        bool is_light,
                                        COLORREF caption_rgb,
                                        COLORREF text_rgb);

namespace vedro {
namespace {

using Microsoft::WRL::ComPtr;

std::string WideToUtf8(const std::wstring& wstr) {
  if (wstr.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring Utf8ToWide(const std::string& str) {
  if (str.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
  if (size <= 1) return {};
  std::wstring out(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, out.data(), size);
  return out;
}

bool IsAllowedHttpUrl(const std::string& url) {
  auto starts_ci = [&](const char* prefix) {
    size_t n = strlen(prefix);
    if (url.size() <= n) return false;
    for (size_t i = 0; i < n; ++i) {
      if (tolower(static_cast<unsigned char>(url[i])) != prefix[i]) return false;
    }
    return true;
  };
  if (!starts_ci("http://") && !starts_ci("https://")) return false;
  for (unsigned char c : url) {
    if (c <= 0x20 || c == '"' || c == '`' || c == '|' || c == ';' || c == '^' || c == '<' || c == '>') {
      return false;
    }
  }
  return true;
}

double QueryWindowsRefreshRateHz(HWND hwnd) {
  DEVMODEW dm = {};
  dm.dmSize = sizeof(dm);
  const wchar_t* dev_name = nullptr;
  MONITORINFOEXW mi = {};
  mi.cbSize = sizeof(mi);
  if (hwnd) {
    HMONITOR mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (GetMonitorInfoW(mon, &mi)) {
      dev_name = mi.szDevice;
    }
  }
  if (EnumDisplaySettingsW(dev_name, ENUM_CURRENT_SETTINGS, &dm) &&
      dm.dmDisplayFrequency >= 24 && dm.dmDisplayFrequency <= 500) {
    return static_cast<double>(dm.dmDisplayFrequency);
  }
  return 60.0;
}

std::vector<std::string> PickFilesWindows(HWND hwnd,
                                          bool allow_directory,
                                          bool allow_multiple,
                                          const std::vector<std::string>& extensions,
                                          const std::string& title) {
  std::vector<std::string> results;
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&dialog)))) {
    return results;
  }

  // On Win32 IFileOpenDialog, FOS_PICKFOLDERS hides ALL files! Only enable folder-pick mode
  // when caller explicitly wants a folder (allow_directory && extensions.empty()).
  const bool pick_folders_only = allow_directory && extensions.empty();

  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    options |= FOS_FORCEFILESYSTEM;
    if (pick_folders_only) {
      options |= FOS_PICKFOLDERS;
    } else if (allow_multiple) {
      options |= FOS_ALLOWMULTISELECT;
    }
    dialog->SetOptions(options);
  }

  if (!title.empty()) {
    std::wstring wtitle = Utf8ToWide(title);
    dialog->SetTitle(wtitle.c_str());
  }

  std::wstring spec;
  if (!pick_folders_only && !extensions.empty()) {
    for (size_t i = 0; i < extensions.size(); ++i) {
      if (i > 0) spec += L";";
      spec += L"*." + Utf8ToWide(extensions[i]);
    }
    COMDLG_FILTERSPEC filter[2] = {
        {L"Supported Files", spec.c_str()},
        {L"All Files", L"*.*"},
    };
    dialog->SetFileTypes(2, filter);
  }

  if (SUCCEEDED(dialog->Show(hwnd))) {
    ComPtr<IShellItemArray> items;
    if (allow_multiple && !pick_folders_only && SUCCEEDED(dialog->GetResults(&items))) {
      DWORD count = 0;
      if (SUCCEEDED(items->GetCount(&count))) {
        for (DWORD i = 0; i < count; ++i) {
          ComPtr<IShellItem> item;
          if (SUCCEEDED(items->GetItemAt(i, &item))) {
            PWSTR path = nullptr;
            if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
              results.push_back(WideToUtf8(path));
              CoTaskMemFree(path);
            }
          }
        }
      }
    } else {
      ComPtr<IShellItem> item;
      if (SUCCEEDED(dialog->GetResult(&item))) {
        PWSTR path = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
          results.push_back(WideToUtf8(path));
          CoTaskMemFree(path);
        }
      }
    }
  }
  return results;
}

struct WindowModeState {
  bool is_fullscreen = false;
  bool always_on_top = false;
  DWORD saved_style = 0;
  WINDOWPLACEMENT saved_placement = {sizeof(WINDOWPLACEMENT)};
};

bool SetWindowsFullscreen(HWND hwnd, WindowModeState* state, bool enable) {
  if (!hwnd || !state) return false;
  if (state->is_fullscreen == enable) return enable;

  if (enable) {
    state->saved_style = static_cast<DWORD>(GetWindowLong(hwnd, GWL_STYLE));
    GetWindowPlacement(hwnd, &state->saved_placement);
    MONITORINFO mi = {sizeof(MONITORINFO)};
    if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY), &mi)) {
      VedroSetWin32FullscreenFlag(true);
      const MARGINS zero_margins = {0, 0, 0, 0};
      DwmExtendFrameIntoClientArea(hwnd, &zero_margins);
      SetWindowLong(hwnd, GWL_STYLE, state->saved_style & ~WS_OVERLAPPEDWINDOW);
      SetWindowPos(
          hwnd,
          state->always_on_top ? HWND_TOPMOST : HWND_TOP,
          mi.rcMonitor.left,
          mi.rcMonitor.top,
          mi.rcMonitor.right - mi.rcMonitor.left,
          mi.rcMonitor.bottom - mi.rcMonitor.top,
          SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
      state->is_fullscreen = true;
    }
  } else {
    VedroSetWin32FullscreenFlag(false);
    SetWindowLong(hwnd, GWL_STYLE, state->saved_style != 0 ? state->saved_style : WS_OVERLAPPEDWINDOW);
    const MARGINS margins = {0, 0, 0, 1};
    DwmExtendFrameIntoClientArea(hwnd, &margins);
    SetWindowPlacement(hwnd, &state->saved_placement);
    SetWindowPos(
        hwnd,
        state->always_on_top ? HWND_TOPMOST : HWND_NOTOPMOST,
        0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    state->is_fullscreen = false;
  }
  return state->is_fullscreen;
}

struct WindowsDisplayCaps {
  bool supports_hdr10 = false;
  int max_luminance_nits = 400;
};

WindowsDisplayCaps ProbeDxgiHdrCapabilities(HWND hwnd) {
  WindowsDisplayCaps caps;
  ComPtr<IDXGIFactory6> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
    return caps;
  }
  HMONITOR target_mon = hwnd ? MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) : nullptr;
  WindowsDisplayCaps fallback_caps;
  ComPtr<IDXGIAdapter1> adapter;
  for (UINT i = 0; SUCCEEDED(factory->EnumAdapters1(i, &adapter)); ++i) {
    ComPtr<IDXGIOutput> output;
    for (UINT j = 0; SUCCEEDED(adapter->EnumOutputs(j, &output)); ++j) {
      ComPtr<IDXGIOutput6> output6;
      if (SUCCEEDED(output.As(&output6))) {
        DXGI_OUTPUT_DESC1 desc = {};
        if (SUCCEEDED(output6->GetDesc1(&desc))) {
          if (desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020) {
            WindowsDisplayCaps cur;
            cur.supports_hdr10 = true;
            cur.max_luminance_nits = desc.MaxLuminance > 100.0f
                                         ? static_cast<int>(desc.MaxLuminance)
                                         : 1000;
            if (!target_mon || desc.Monitor == target_mon) {
              return cur;
            }
            fallback_caps = cur;
          } else if (target_mon && desc.Monitor == target_mon) {
            return caps;
          }
        }
      }
      output.Reset();
    }
    adapter.Reset();
  }
  return fallback_caps;
}

bool ProbeWasapiExclusiveAtmosSupport() {
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&enumerator)))) {
    return false;
  }
  ComPtr<IMMDevice> device;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device))) {
    return false;
  }
  ComPtr<IAudioClient> client;
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                              reinterpret_cast<void**>(client.GetAddressOf())))) {
    return false;
  }

  auto probe_subtype = [&](const GUID& subformat, WORD channels, DWORD rate, DWORD mask) -> bool {
    WAVEFORMATEXTENSIBLE fmt = {};
    fmt.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    fmt.Format.nChannels = channels;
    fmt.Format.nSamplesPerSec = rate;
    fmt.Format.wBitsPerSample = 16;
    fmt.Format.nBlockAlign = fmt.Format.nChannels * (fmt.Format.wBitsPerSample / 8);
    fmt.Format.nAvgBytesPerSec = fmt.Format.nSamplesPerSec * fmt.Format.nBlockAlign;
    fmt.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
    fmt.Samples.wValidBitsPerSample = 16;
    fmt.dwChannelMask = mask;
    fmt.SubFormat = subformat;
    return client->IsFormatSupported(AUDCLNT_SHAREMODE_EXCLUSIVE,
                                     reinterpret_cast<WAVEFORMATEX*>(&fmt),
                                     nullptr) == S_OK;
  };

  if (probe_subtype(KSDATAFORMAT_SUBTYPE_IEC61937_DOLBY_MLP, 8, 192000,
                    KSAUDIO_SPEAKER_7POINT1_SURROUND)) {
    return true;
  }
  return probe_subtype(KSDATAFORMAT_SUBTYPE_IEC61937_DOLBY_DIGITAL_PLUS, 2, 192000,
                       KSAUDIO_SPEAKER_STEREO);
}

std::string SaveScreenshotWindows(const std::vector<uint8_t>& bytes, const std::string& raw_name) {
  if (bytes.empty()) return {};
  PWSTR pics_path = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Pictures, 0, nullptr, &pics_path)) || !pics_path) {
    return {};
  }
  std::wstring dir = std::wstring(pics_path) + L"\\Vedro";
  CoTaskMemFree(pics_path);
  CreateDirectoryW(dir.c_str(), nullptr);
  std::string clean;
  for (unsigned char c : raw_name) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
        c == '.' || c == '_' || c == '-') {
      clean.push_back(static_cast<char>(c));
    } else {
      clean.push_back('_');
    }
  }
  if (clean.empty()) clean = "vedro_screenshot.png";
  std::wstring full = dir + L"\\" + Utf8ToWide(clean);
  std::ofstream ofs(full, std::ios::binary | std::ios::trunc);
  if (!ofs.is_open()) return {};
  ofs.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  ofs.close();
  return WideToUtf8(full);
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_hw_channel;

}  // namespace

void NotifyWindowsDroppedFiles(const std::vector<std::string>& paths) {
  if (!g_hw_channel || paths.empty()) return;
  flutter::EncodableList list;
  for (const auto& p : paths) {
    list.push_back(flutter::EncodableValue(p));
  }
  flutter::EncodableMap args = {
      {flutter::EncodableValue("paths"), flutter::EncodableValue(std::move(list))},
  };
  g_hw_channel->InvokeMethod("filesDropped",
                             std::make_unique<flutter::EncodableValue>(std::move(args)));
}

void UnregisterVedroHardwarePlugin() {
  SetThreadExecutionState(ES_CONTINUOUS);
  if (g_hw_channel) {
    g_hw_channel->SetMethodCallHandler(nullptr);
    g_hw_channel.reset();
  }
}

void RegisterVedroHardwarePlugin(flutter::BinaryMessenger* messenger, HWND hwnd) {
  UnregisterVedroHardwarePlugin();
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.vedro.player/hardware",
      &flutter::StandardMethodCodec::GetInstance());

  auto mode_state = std::make_shared<WindowModeState>();

  channel->SetMethodCallHandler(
      [hwnd, mode_state](const flutter::MethodCall<flutter::EncodableValue>& call,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto& method = call.method_name();
        if (method == "queryCapabilities") {
          auto display = ProbeDxgiHdrCapabilities(hwnd);
          bool atmos_bitstream = ProbeWasapiExclusiveAtmosSupport();
          flutter::EncodableMap map = {
              {flutter::EncodableValue("is_tv"), flutter::EncodableValue(false)},
              {flutter::EncodableValue("has_touchscreen"), flutter::EncodableValue(false)},
              {flutter::EncodableValue("supports_pip"), flutter::EncodableValue(false)},
              {flutter::EncodableValue("supports_hdr10"),
               flutter::EncodableValue(display.supports_hdr10)},
              {flutter::EncodableValue("supports_hlg"),
               flutter::EncodableValue(display.supports_hdr10)},
              {flutter::EncodableValue("supports_native_dolby_vision"),
               flutter::EncodableValue(false)},
              {flutter::EncodableValue("supports_atmos_bitstream"),
               flutter::EncodableValue(atmos_bitstream)},
              {flutter::EncodableValue("supports_spatial_audio"),
               flutter::EncodableValue(true)},
              {flutter::EncodableValue("max_luminance_nits"),
               flutter::EncodableValue(display.max_luminance_nits)},
              {flutter::EncodableValue("refresh_rate_hz"),
               flutter::EncodableValue(QueryWindowsRefreshRateHz(hwnd))},
          };
          result->Success(flutter::EncodableValue(map));
        } else if (method == "createVideoSurface") {
          result->Success(flutter::EncodableValue(reinterpret_cast<int64_t>(hwnd)));
        } else if (method == "isFullscreen") {
          result->Success(flutter::EncodableValue(mode_state->is_fullscreen));
        } else if (method == "toggleFullscreen") {
          bool next = SetWindowsFullscreen(hwnd, mode_state.get(), !mode_state->is_fullscreen);
          result->Success(flutter::EncodableValue(next));
        } else if (method == "setFullscreen") {
          bool enabled = false;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) {
                enabled = *b;
              }
            }
          }
          bool next = SetWindowsFullscreen(hwnd, mode_state.get(), enabled);
          result->Success(flutter::EncodableValue(next));
        } else if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(hwnd != nullptr && IsZoomed(hwnd) != FALSE));
        } else if (method == "toggleZoom") {
          bool zoomed = false;
          if (hwnd) {
            ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
            zoomed = IsZoomed(hwnd) != FALSE;
          }
          result->Success(flutter::EncodableValue(zoomed));
        } else if (method == "minimizeWindow") {
          if (hwnd) {
            ShowWindow(hwnd, SW_MINIMIZE);
          }
          result->Success();
        } else if (method == "closeWindow") {
          if (hwnd) {
            PostMessage(hwnd, WM_CLOSE, 0, 0);
          }
          result->Success();
        } else if (method == "startWindowDrag") {
          if (hwnd && !mode_state->is_fullscreen) {
            POINT pt = {};
            GetCursorPos(&pt);
            ReleaseCapture();
            PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, MAKELPARAM(pt.x, pt.y));
          }
          result->Success();
        } else if (method == "startWindowResize") {
          std::string edge;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto eit = args->find(flutter::EncodableValue("edge"));
            if (eit != args->end()) {
              if (const auto* s = std::get_if<std::string>(&eit->second)) edge = *s;
            }
          }
          if (hwnd && !mode_state->is_fullscreen && !IsZoomed(hwnd)) {
            WPARAM ht = 0;
            if (edge == "left") ht = HTLEFT;
            else if (edge == "right") ht = HTRIGHT;
            else if (edge == "top") ht = HTTOP;
            else if (edge == "bottom") ht = HTBOTTOM;
            else if (edge == "topLeft") ht = HTTOPLEFT;
            else if (edge == "topRight") ht = HTTOPRIGHT;
            else if (edge == "bottomLeft") ht = HTBOTTOMLEFT;
            else if (edge == "bottomRight") ht = HTBOTTOMRIGHT;
            if (ht != 0) {
              POINT pt = {};
              GetCursorPos(&pt);
              ReleaseCapture();
              PostMessage(hwnd, WM_NCLBUTTONDOWN, ht, MAKELPARAM(pt.x, pt.y));
            }
          }
          result->Success();
        } else if (method == "showWindowSystemMenu") {
          if (hwnd && !mode_state->is_fullscreen) {
            HMENU menu = GetSystemMenu(hwnd, FALSE);
            if (menu) {
              const bool zoomed = IsZoomed(hwnd) != FALSE;
              EnableMenuItem(menu, SC_RESTORE, MF_BYCOMMAND | (zoomed ? MF_ENABLED : MF_GRAYED));
              EnableMenuItem(menu, SC_MOVE, MF_BYCOMMAND | (!zoomed ? MF_ENABLED : MF_GRAYED));
              EnableMenuItem(menu, SC_SIZE, MF_BYCOMMAND | (!zoomed ? MF_ENABLED : MF_GRAYED));
              EnableMenuItem(menu, SC_MAXIMIZE, MF_BYCOMMAND | (!zoomed ? MF_ENABLED : MF_GRAYED));
              POINT pt = {};
              GetCursorPos(&pt);
              int cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                       pt.x, pt.y, 0, hwnd, nullptr);
              if (cmd != 0) {
                PostMessage(hwnd, WM_SYSCOMMAND, static_cast<WPARAM>(cmd), 0);
              }
            }
          }
          result->Success();
        } else if (method == "setAlwaysOnTop") {
          bool enabled = false;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) {
                enabled = *b;
              }
            }
          }
          mode_state->always_on_top = enabled;
          SetWindowPos(hwnd, enabled ? HWND_TOPMOST : HWND_NOTOPMOST,
                       0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          result->Success(flutter::EncodableValue(enabled));
        } else if (method == "pickFiles") {
          bool allow_dir = false;
          bool allow_multiple = false;
          std::vector<std::string> exts;
          std::string title = "Select File";
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto dir_it = args->find(flutter::EncodableValue("allow_directory"));
            if (dir_it != args->end()) {
              if (const auto* b = std::get_if<bool>(&dir_it->second)) allow_dir = *b;
            }
            auto mul_it = args->find(flutter::EncodableValue("allow_multiple"));
            if (mul_it != args->end()) {
              if (const auto* b = std::get_if<bool>(&mul_it->second)) allow_multiple = *b;
            }
            auto title_it = args->find(flutter::EncodableValue("title"));
            if (title_it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&title_it->second)) title = *s;
            }
            auto ext_it = args->find(flutter::EncodableValue("extensions"));
            if (ext_it != args->end()) {
              if (const auto* list = std::get_if<flutter::EncodableList>(&ext_it->second)) {
                for (const auto& item : *list) {
                  if (const auto* s = std::get_if<std::string>(&item)) exts.push_back(*s);
                }
              }
            }
          }
          auto picked = PickFilesWindows(hwnd, allow_dir, allow_multiple, exts, title);
          flutter::EncodableList out;
          for (const auto& p : picked) out.push_back(flutter::EncodableValue(p));
          result->Success(flutter::EncodableValue(out));
        } else if (method == "setKeepScreenOn") {
          bool enabled = false;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) {
                enabled = *b;
              }
            }
          }
          SetThreadExecutionState(enabled
                                      ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED)
                                      : ES_CONTINUOUS);
          result->Success();
        } else if (method == "setWindowChrome") {
          bool is_light = false;
          int64_t canvas_argb = 0xFF0B0B0D;
          int64_t fg_argb = 0xFFF4F4F6;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto lit = args->find(flutter::EncodableValue("is_light"));
            if (lit != args->end()) {
              if (const auto* b = std::get_if<bool>(&lit->second)) is_light = *b;
            }
            auto cit = args->find(flutter::EncodableValue("canvas_argb"));
            if (cit != args->end()) {
              if (const auto* i64 = std::get_if<int64_t>(&cit->second)) canvas_argb = *i64;
              else if (const auto* i32 = std::get_if<int32_t>(&cit->second)) canvas_argb = static_cast<uint32_t>(*i32);
            }
            auto fit = args->find(flutter::EncodableValue("fg_argb"));
            if (fit != args->end()) {
              if (const auto* i64 = std::get_if<int64_t>(&fit->second)) fg_argb = *i64;
              else if (const auto* i32 = std::get_if<int32_t>(&fit->second)) fg_argb = static_cast<uint32_t>(*i32);
            }
          }
          COLORREF cap_rgb = RGB((canvas_argb >> 16) & 0xFF, (canvas_argb >> 8) & 0xFF, canvas_argb & 0xFF);
          COLORREF txt_rgb = RGB((fg_argb >> 16) & 0xFF, (fg_argb >> 8) & 0xFF, fg_argb & 0xFF);
          VedroApplyWin32WindowChrome(hwnd, is_light, cap_rgb, txt_rgb);
          result->Success();
        } else if (method == "saveScreenshotToGallery") {
          std::string saved;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto bit = args->find(flutter::EncodableValue("bytes"));
            auto nit = args->find(flutter::EncodableValue("file_name"));
            std::string name = "vedro_screenshot.png";
            if (nit != args->end()) {
              if (const auto* s = std::get_if<std::string>(&nit->second)) name = *s;
            }
            if (bit != args->end()) {
              if (const auto* vec = std::get_if<std::vector<uint8_t>>(&bit->second)) {
                saved = SaveScreenshotWindows(*vec, name);
              }
            }
          }
          if (saved.empty()) {
            result->Success();
          } else {
            result->Success(flutter::EncodableValue(saved));
          }
        } else if (method == "openUrl" || method == "launchExternalPlayer") {
          std::string url;
          std::string player;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto uit = args->find(flutter::EncodableValue("url"));
            if (uit != args->end()) {
              if (const auto* s = std::get_if<std::string>(&uit->second)) url = *s;
            }
            auto pit = args->find(flutter::EncodableValue("player"));
            if (pit != args->end()) {
              if (const auto* s = std::get_if<std::string>(&pit->second)) player = *s;
            }
          }
          if (!IsAllowedHttpUrl(url)) {
            result->Success(flutter::EncodableValue(false));
          } else {
            bool ok = false;
            if (method == "launchExternalPlayer" && (player == "mpv" || player == "vlc")) {
              std::wstring exe = player == "mpv" ? L"mpv.exe" : L"vlc.exe";
              std::wstring params = L"\"" + Utf8ToWide(url) + L"\"";
              HINSTANCE inst = ShellExecuteW(hwnd, L"open", exe.c_str(), params.c_str(), nullptr, SW_SHOWNORMAL);
              ok = reinterpret_cast<INT_PTR>(inst) > 32;
            }
            if (!ok) {
              std::string target_uri = url;
              if (method == "launchExternalPlayer" && player == "potplayer") {
                target_uri = "potplayer://" + url;
              }
              std::wstring wurl = Utf8ToWide(target_uri);
              HINSTANCE inst = ShellExecuteW(hwnd, L"open", wurl.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
              ok = reinterpret_cast<INT_PTR>(inst) > 32;
              if (!ok && target_uri != url) {
                std::wstring wfallback = Utf8ToWide(url);
                inst = ShellExecuteW(hwnd, L"open", wfallback.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
                ok = reinterpret_cast<INT_PTR>(inst) > 32;
              }
            }
            result->Success(flutter::EncodableValue(ok));
          }
        } else if (method == "installUpdatePackage") {
          std::string path;
          bool silent = true;
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto pit = args->find(flutter::EncodableValue("path"));
            if (pit != args->end()) {
              if (const auto* s = std::get_if<std::string>(&pit->second)) path = *s;
            }
            auto sit = args->find(flutter::EncodableValue("silent"));
            if (sit != args->end()) {
              if (const auto* b = std::get_if<bool>(&sit->second)) silent = *b;
            }
          }
          std::wstring wpath = Utf8ToWide(path);
          DWORD attrs = wpath.empty() ? INVALID_FILE_ATTRIBUTES : GetFileAttributesW(wpath.c_str());
          bool ends_exe = path.size() >= 4 &&
                          _stricmp(path.c_str() + path.size() - 4, ".exe") == 0;
          if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY) || !ends_exe) {
            flutter::EncodableMap err = {
                {flutter::EncodableValue("ok"), flutter::EncodableValue(false)},
                {flutter::EncodableValue("message"),
                 flutter::EncodableValue("无效的 Windows 安装程序 (.exe)")},
            };
            result->Success(flutter::EncodableValue(err));
          } else {
            const wchar_t* params = silent
                                        ? L"/SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"
                                        : L"/CLOSEAPPLICATIONS /RESTARTAPPLICATIONS";
            HINSTANCE inst = ShellExecuteW(hwnd, L"open", wpath.c_str(), params, nullptr, SW_SHOWNORMAL);
            bool ok = reinterpret_cast<INT_PTR>(inst) > 32;
            flutter::EncodableMap resp = {
                {flutter::EncodableValue("ok"), flutter::EncodableValue(ok)},
                {flutter::EncodableValue("message"),
                 ok ? flutter::EncodableValue()
                    : flutter::EncodableValue("启动安装程序失败，请尝试手动运行")},
            };
            result->Success(flutter::EncodableValue(resp));
            if (ok && hwnd) {
              PostMessage(hwnd, WM_CLOSE, 0, 0);
            }
          }
        } else {
          result->NotImplemented();
        }
      });

  g_hw_channel = std::move(channel);
}

}  // namespace vedro
