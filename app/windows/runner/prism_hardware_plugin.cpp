#include "prism_hardware_plugin.h"

#include <dxgi1_6.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <ks.h>
#include <ksmedia.h>
#include <wrl/client.h>

#include <memory>
#include <string>

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "ole32.lib")

namespace prism {
namespace {

using Microsoft::WRL::ComPtr;

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

  // Test IEC 61937 TrueHD / Dolby Digital Plus (Atmos) exclusive bitstream acceptance
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

void RegisterPrismHardwarePlugin(flutter::BinaryMessenger* messenger, HWND hwnd) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.prismplayer/hardware",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [hwnd](const flutter::MethodCall<flutter::EncodableValue>& call,
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
        } else {
          result->NotImplemented();
        }
      });

  // Intentionally leaked for process lifetime (matches Flutter Windows runner convention).
  channel.release();
}

}  // namespace prism
