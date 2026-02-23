import Flutter
import UIKit
import CoreTelephony
import CoreMotion

public class GpsPlusPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private var eventSink: FlutterEventSink?
    private var lastStepCount: Int = 0

    /// Sensor update interval (20ms = SENSOR_DELAY_GAME equivalent).
    private let sensorInterval: TimeInterval = 0.02

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "gps_plus", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "gps_plus/sensors", binaryMessenger: registrar.messenger())

        let instance = GpsPlusPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - FlutterPlugin

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCellTowers":
            getCellTowers(result: result)
        case "startSensors":
            startSensors(result: result)
        case "stopSensors":
            stopSensors(result: result)
        case "hasSensors":
            hasSensors(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - Sensor methods

    private func hasSensors(result: @escaping FlutterResult) {
        let hasSteps = CMPedometer.isStepCountingAvailable()
        let hasAccel = motionManager.isAccelerometerAvailable
        let hasGyroOrMag = motionManager.isGyroAvailable || motionManager.isMagnetometerAvailable
        result(hasSteps && hasAccel && hasGyroOrMag)
    }

    private func startSensors(result: @escaping FlutterResult) {
        startAccelerometer()
        startGyroscope()
        startMagnetometer()
        startPedometer()
        result(true)
    }

    private func stopSensors(result: @escaping FlutterResult) {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopMagnetometerUpdates()
        pedometer.stopUpdates()
        lastStepCount = 0
        result(true)
    }

    // MARK: - Accelerometer

    private func startAccelerometer() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = sensorInterval

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data, let sink = self.eventSink else { return }

            // iOS CMAcceleration is in G's — convert to m/s² (Android format)
            let event: [String: Any] = [
                "type": "accel",
                "x": data.acceleration.x * 9.81,
                "y": data.acceleration.y * 9.81,
                "z": data.acceleration.z * 9.81,
                "timestamp": Int64(data.timestamp * 1_000_000_000)
            ]
            sink(event)
        }
    }

    // MARK: - Gyroscope

    private func startGyroscope() {
        guard motionManager.isGyroAvailable else { return }
        motionManager.gyroUpdateInterval = sensorInterval

        motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data, let sink = self.eventSink else { return }

            // iOS gyro is already in rad/s — matches Android
            let event: [String: Any] = [
                "type": "gyro",
                "x": data.rotationRate.x,
                "y": data.rotationRate.y,
                "z": data.rotationRate.z,
                "timestamp": Int64(data.timestamp * 1_000_000_000)
            ]
            sink(event)
        }
    }

    // MARK: - Magnetometer

    private func startMagnetometer() {
        guard motionManager.isMagnetometerAvailable else { return }
        motionManager.magnetometerUpdateInterval = sensorInterval

        motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data, let sink = self.eventSink else { return }

            // iOS CMMagneticField is already in µT — matches Android
            let event: [String: Any] = [
                "type": "mag",
                "x": data.magneticField.x,
                "y": data.magneticField.y,
                "z": data.magneticField.z,
                "timestamp": Int64(data.timestamp * 1_000_000_000)
            ]
            sink(event)
        }
    }

    // MARK: - Pedometer (step counting)

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        lastStepCount = 0

        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self = self, let data = data, let sink = self.eventSink else { return }

            let currentSteps = data.numberOfSteps.intValue
            let newSteps = currentSteps - self.lastStepCount

            // Emit one step event per new step (CMPedometer gives cumulative count)
            if newSteps > 0 {
                let timestamp = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
                for _ in 0..<newSteps {
                    let event: [String: Any] = [
                        "type": "step",
                        "timestamp": timestamp
                    ]
                    sink(event)
                }
                self.lastStepCount = currentSteps
            }
        }
    }

    // MARK: - Cell towers (existing)

    private func getCellTowers(result: @escaping FlutterResult) {
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

                let tower: [String: Any] = [
                    "cid": 0,
                    "lac": 0,
                    "mcc": mcc,
                    "mnc": mnc,
                    "rssi": -1,
                    "type": radioType,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]
                towers.append(tower)
            }
        } else {
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
