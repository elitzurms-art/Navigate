#ifndef FLUTTER_PLUGIN_GPS_PLUS_PLUGIN_H_
#define FLUTTER_PLUGIN_GPS_PLUS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace gps_plus {

class GpsPlusPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  GpsPlusPlugin();

  virtual ~GpsPlusPlugin();

  GpsPlusPlugin(const GpsPlusPlugin&) = delete;
  GpsPlusPlugin& operator=(const GpsPlusPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace gps_plus

#endif  // FLUTTER_PLUGIN_GPS_PLUS_PLUGIN_H_
