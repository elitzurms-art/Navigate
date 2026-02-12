#include "include/gps_plus/gps_plus_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "gps_plus_plugin.h"

void GpsPlusPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  gps_plus::GpsPlusPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
