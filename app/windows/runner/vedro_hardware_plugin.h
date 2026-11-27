#ifndef RUNNER_VEDRO_HARDWARE_PLUGIN_H_
#define RUNNER_VEDRO_HARDWARE_PLUGIN_H_

#include <flutter/binary_messenger.h>
#include <windows.h>
#include <string>
#include <vector>

namespace vedro {

// Registers the native Windows DXGI 1.6 HDR/Dolby Vision + WASAPI Exclusive Atmos
// capability detector and Win32 execution-state controller.
void RegisterVedroHardwarePlugin(flutter::BinaryMessenger* messenger, HWND hwnd);
void UnregisterVedroHardwarePlugin();
void NotifyWindowsDroppedFiles(const std::vector<std::string>& paths);

}  // namespace vedro

#endif  // RUNNER_VEDRO_HARDWARE_PLUGIN_H_
