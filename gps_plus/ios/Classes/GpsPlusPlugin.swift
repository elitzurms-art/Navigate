import Flutter
import UIKit
import CoreTelephony

public class GpsPlusPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "gps_plus", binaryMessenger: registrar.messenger())
        let instance = GpsPlusPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCellTowers":
            getCellTowers(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func getCellTowers(result: @escaping FlutterResult) {
        // iOS does not provide raw cell tower IDs since iOS 12+.
        // We can only get carrier information via CTTelephonyNetworkInfo.
        // Return carrier metadata so the Dart side knows the network context.

        let networkInfo = CTTelephonyNetworkInfo()
        var towers: [[String: Any]] = []

        if #available(iOS 12.0, *) {
            guard let carriers = networkInfo.serviceSubscriberCellularProviders else {
                result(towers)
                return
            }

            for (serviceId, carrier) in carriers {
                guard let mccStr = carrier.mobileCountryCode,
                      let mncStr = carrier.mobileNetworkCode,
                      let mcc = Int(mccStr),
                      let mnc = Int(mncStr) else {
                    continue
                }

                var radioType = "gsm"
                if let radioTech = networkInfo.serviceCurrentRadioAccessTechnology?[serviceId] {
                    radioType = mapRadioTechnology(radioTech)
                }

                // iOS doesn't expose CID/LAC, so we use placeholder values.
                // The Dart side should detect cid=0 as "iOS limited mode".
                let tower: [String: Any] = [
                    "cid": 0,
                    "lac": 0,
                    "mcc": mcc,
                    "mnc": mnc,
                    "rssi": -1,  // Not available on iOS
                    "type": radioType,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]
                towers.append(tower)
            }
        } else {
            // iOS < 12 fallback
            if let carrier = networkInfo.subscriberCellularProvider,
               let mccStr = carrier.mobileCountryCode,
               let mncStr = carrier.mobileNetworkCode,
               let mcc = Int(mccStr),
               let mnc = Int(mncStr) {

                let tower: [String: Any] = [
                    "cid": 0,
                    "lac": 0,
                    "mcc": mcc,
                    "mnc": mnc,
                    "rssi": -1,
                    "type": "gsm",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]
                towers.append(tower)
            }
        }

        result(towers)
    }

    private func mapRadioTechnology(_ tech: String) -> String {
        switch tech {
        case CTRadioAccessTechnologyGPRS,
             CTRadioAccessTechnologyEdge,
             CTRadioAccessTechnologyCDMA1x:
            return "gsm"
        case CTRadioAccessTechnologyWCDMA,
             CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD:
            return "umts"
        case CTRadioAccessTechnologyLTE:
            return "lte"
        default:
            if #available(iOS 14.1, *) {
                if tech == CTRadioAccessTechnologyNRNSA || tech == CTRadioAccessTechnologyNR {
                    return "nr"
                }
            }
            return "lte"
        }
    }
}
