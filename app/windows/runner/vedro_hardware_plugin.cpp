#include "vedro_hardware_plugin.h"

#include <dxgi1_6.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <ks.h>
#include <ksmedia.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <memory>
#include <string>
#include <vector>

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

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

std::vector<std::string> PickFilesWindows(HWND hwnd,
                                          bool allow_directory,
                                          const std::vector<std::string>& extensions,
                                          const std::string& title) {
  std::vector<std::string> results;
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&dialog)))) {
    return results;
  }

  DWORD options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    options |= FOS_FORCEFILESYSTEM;
    if (allow_directory) {
      options |= FOS_PICKFOLDERS;
    }
    dialog->SetOptions(options);
  }

  if (!title.empty()) {
    std::wstring wtitle = Utf8ToWide(title);
    dialog->SetTitle(wtitle.c_str());
  }

  std::wstring spec;
  if (!allow_directory && !extensions.empty()) {
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
    ComPtr<IShellItem> item;
    if (SUCCEEDED(dialog->GetResult(&item))) {
      PWSTR path = nullptr;
      if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
        results.push_back(WideToUtf8(path));
        CoTaskMemFree(path);
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
    SetWindowLong(hwnd, GWL_STYLE, state->saved_style != 0 ? state->saved_style : WS_OVERLAPPEDWINDOW);
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

WindowsDisplayCaps ProbeDxgiHdrCapabilities() {
  WindowsDisplayCaps caps;
  ComPtr<IDXGIFactory6> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
    return caps;
  }
  ComPtr<IDXGIAdapter1> adapter;
  for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
    ComPtr<IDXGIOutput> output;
    for (UINT j = 0; adapter->EnumOutputs(j, &output) != DXGI_ERROR_NOT_FOUND; ++j) {
      ComPtr<IDXGIOutput6> output6;
      if (SUCCEEDED(output.As(&output6))) {
        DXGI_OUTPUT_DESC1 desc = {};
        if (SUCCEEDED(output6->GetDesc1(&desc))) {
          if (desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020) {
            caps.supports_hdr10 = true;
            if (desc.MaxLuminance > 100.0f) {
              caps.max_luminance_nits = static_cast<int>(desc.MaxLuminance);
            } else {
              caps.max_luminance_nits = 1000;
            }
            return caps;
          }
        }
      }
      output.Reset();
    }
    adapter.Reset();
  }
  return caps;
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

  WAVEFORMATEXTENSIBLE fmt = {};
  fmt.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
  fmt.Format.nChannels = 8;
  fmt.Format.nSamplesPerSec = 192000;
  fmt.Format.wBitsPerSample = 16;
  fmt.Format.nBlockAlign = fmt.Format.nChannels * (fmt.Format.wBitsPerSample / 8);
  fmt.Format.nAvgBytesPerSec = fmt.Format.nSamplesPerSec * fmt.Format.nBlockAlign;
  fmt.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
  fmt.Samples.wValidBitsPerSample = 16;
  fmt.dwChannelMask = KSAUDIO_SPEAKER_7POINT1_SURROUND;
  fmt.SubFormat = KSDATAFORMAT_SUBTYPE_IEC61937_DOLBY_MLP;

  return client->IsFormatSupported(AUDCLNT_SHAREMODE_EXCLUSIVE,
                                   reinterpret_cast<WAVEFORMATEX*>(&fmt),
                                   nullptr) == S_OK;
}

}  // namespace

void RegisterVedroHardwarePlugin(flutter::BinaryMessenger* messenger, HWND hwnd) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.vedro.player/hardware",
      &flutter::StandardMethodCodec::GetInstance());

  auto mode_state = std::make_shared<WindowModeState>();

  channel->SetMethodCallHandler(
      [hwnd, mode_state](const flutter::MethodCall<flutter::EncodableValue>& call,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto& method = call.method_name();
        if (method == "queryCapabilities") {
          auto display = ProbeDxgiHdrCapabilities();
          bool atmos_bitstream = ProbeWasapiExclusiveAtmosSupport();
          flutter::EncodableMap map = {
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
               flutter::EncodableValue(60.0)},
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
        } else if (method == "toggleZoom") {
          if (hwnd) {
            ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
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
          std::vector<std::string> exts;
          std::string title = "Select File";
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto dir_it = args->find(flutter::EncodableValue("allow_directory"));
            if (dir_it != args->end()) {
              if (const auto* b = std::get_if<bool>(&dir_it->second)) allow_dir = *b;
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
          auto picked = PickFilesWindows(hwnd, allow_dir, exts, title);
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
          if (url.empty()) {
            result->Success(flutter::EncodableValue(false));
          } else {
            std::string target_uri = url;
            if (method == "launchExternalPlayer" && player == "potplayer") {
              target_uri = "potplayer://" + url;
            }
            std::wstring wurl = Utf8ToWide(target_uri);
            HINSTANCE inst = ShellExecuteW(hwnd, L"open", wurl.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            bool ok = reinterpret_cast<INT_PTR>(inst) > 32;
            if (!ok && target_uri != url) {
              std::wstring wfallback = Utf8ToWide(url);
              inst = ShellExecuteW(hwnd, L"open", wfallback.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
              ok = reinterpret_cast<INT_PTR>(inst) > 32;
            }
            result->Success(flutter::EncodableValue(ok));
          }
        } else {
          result->NotImplemented();
        }
      });

  channel.release();
}

}  // namespace vedro
