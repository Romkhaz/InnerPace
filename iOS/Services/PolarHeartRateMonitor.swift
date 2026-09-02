import CoreBluetooth
import Foundation
import Observation

/// Подключение к нагрудному пульсометру по стандартному профилю Heart Rate (BLE).
/// Polar H10 отдаёт пульс раз в секунду.
@Observable
final class PolarHeartRateMonitor: NSObject {
    enum State: Equatable {
        case unavailable
        case poweredOff
        case unauthorized
        case idle
        case scanning
        case connecting(String)
        case connected(String)

        var label: String {
            switch self {
            case .unavailable: return "Bluetooth недоступен"
            case .poweredOff: return "Bluetooth выключен"
            case .unauthorized: return "Нет доступа к Bluetooth"
            case .idle: return "Не подключён"
            case .scanning: return "Поиск пульсометра…"
            case .connecting(let name): return "Подключение: \(name)"
            case .connected(let name): return name
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private(set) var state: State = .idle
    private(set) var heartRate: Int?
    private(set) var lastUpdate: Date?
    private(set) var batteryLevel: Int?

    /// Вызывается на главной очереди при каждом новом значении пульса.
    var onHeartRate: ((Int, Date) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var wantsConnection = false

    private let heartRateService = CBUUID(string: "180D")
    private let heartRateMeasurement = CBUUID(string: "2A37")
    private let batteryService = CBUUID(string: "180F")
    private let batteryLevelCharacteristic = CBUUID(string: "2A19")
    private let savedIdentifierKey = "polar.peripheral.identifier"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var isFresh: Bool {
        guard let lastUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 10
    }

    func connect() {
        wantsConnection = true
        guard central.state == .poweredOn else { return }
        startScanOrReconnect()
    }

    func disconnect() {
        wantsConnection = false
        central.stopScan()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        state = .idle
    }

    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: savedIdentifierKey)
    }

    private func startScanOrReconnect() {
        if let saved = UserDefaults.standard.string(forKey: savedIdentifierKey),
           let uuid = UUID(uuidString: saved),
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            connect(to: known)
            return
        }
        state = .scanning
        central.scanForPeripherals(withServices: [heartRateService], options: nil)
    }

    private func connect(to candidate: CBPeripheral) {
        central.stopScan()
        peripheral = candidate
        candidate.delegate = self
        state = .connecting(candidate.name ?? "Пульсометр")
        central.connect(candidate, options: nil)
    }

    private func parseHeartRate(_ data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        if flags & 0x01 == 0 {
            return Int(data[1])
        }
        guard data.count >= 3 else { return nil }
        return Int(data[1]) | (Int(data[2]) << 8)
    }
}

extension PolarHeartRateMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if wantsConnection { startScanOrReconnect() } else { state = .idle }
        case .poweredOff:
            state = .poweredOff
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unavailable
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Первый найденный пульсометр подходит; Polar предпочитаем, если видим несколько.
        let name = peripheral.name ?? ""
        if self.peripheral == nil || name.localizedCaseInsensitiveContains("polar") {
            connect(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedIdentifierKey)
        state = .connected(peripheral.name ?? "Пульсометр")
        peripheral.discoverServices([heartRateService, batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard wantsConnection else { return }
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        heartRate = nil
        guard wantsConnection else {
            state = .idle
            return
        }
        // Система сама подключит датчик, как только он снова появится в эфире.
        state = .connecting(peripheral.name ?? "Пульсометр")
        central.connect(peripheral, options: nil)
    }
}

extension PolarHeartRateMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            if service.uuid == heartRateService {
                peripheral.discoverCharacteristics([heartRateMeasurement], for: service)
            } else if service.uuid == batteryService {
                peripheral.discoverCharacteristics([batteryLevelCharacteristic], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == heartRateMeasurement {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == batteryLevelCharacteristic {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if characteristic.uuid == heartRateMeasurement, let bpm = parseHeartRate(data), bpm > 0 {
            let now = Date()
            heartRate = bpm
            lastUpdate = now
            onHeartRate?(bpm, now)
        } else if characteristic.uuid == batteryLevelCharacteristic, let level = data.first {
            batteryLevel = Int(level)
        }
    }
}
