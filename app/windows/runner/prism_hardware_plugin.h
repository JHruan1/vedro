#ifndef RUNNER_PRISM_HARDWARE_PLUGIN_H_
#define RUNNER_PRISM_HARDWARE_PLUGIN_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

namespace prism {

// Registers the native Windows DXGI 1.6 HDR/Dolby Vision + WASAPI Exclusive Atmos
// capability detector and Win32 execution-state controller.
void RegisterPrismHardwarePlugin(flutter::BinaryMessenger* messenger, HWND hwnd);

}  // namespace prism

#endif  // RUNNER_PRISM_HARDWARE_PLUGIN_H_
