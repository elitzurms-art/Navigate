#include "gps_plus_plugin.h"

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <vector>

namespace gps_plus {

void GpsPlusPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "gps_plus",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<GpsPlusPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

GpsPlusPlugin::GpsPlusPlugin() {}

GpsPlusPlugin::~GpsPlusPlugin() {}

void GpsPlusPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getCellTowers") == 0) {
    // Windows cellular API access requires the Mobile Broadband API
    // (Windows.Networking.NetworkOperators). This is only available on
    // devices with a cellular modem (tablets, laptops with WWAN).
    //
    // For desktop PCs without a cellular modem, return an empty list.
    // The Dart side will handle the "no towers" case gracefully.
    //
    // Full implementation would use:
    //   MobileBroadbandModem::GetDefault()
    //   -> GetCurrentNetwork() -> serving cell info
    //
    // For now, return empty list - most Windows dev machines lack cellular.
    flutter::EncodableList towers;
    result->Success(flutter::EncodableValue(towers));
  } else {
    result->NotImplemented();
  }
}

}  // namespace gps_plus
