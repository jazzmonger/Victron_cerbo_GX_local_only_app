import Foundation
import Observation
import Security

struct ConnectionSettings: Equatable {
    var host: String
    var port: UInt16
    var useTLS: Bool
    var username: String
    var portalID: String

    static let defaultPassword = "4Thezins"

    static let device = ConnectionSettings(
        host: "192.168.2.220",
        port: 8883,
        useTLS: true,
        username: "remoteconsole",
        portalID: "c0619abda86a"
    )
}

enum BatteryActivity: Equatable {
    case unknown
    case idle
    case charging
    case discharging

    var title: String {
        switch self {
        case .unknown: return "—"
        case .idle: return "Idle"
        case .charging: return "Charging"
        case .discharging: return "Discharging"
        }
    }

    var charges: Bool { self == .charging }
}

struct SystemSnapshot: Equatable {
    var gridAmps: Double?
    var gridFromSystem = false
    var solarWatts: Double?
    var solarName = "Solar"
    var solarState: Int?
    var solarYieldKWh: Double?
    var solarPvVolts: Double?
    var solarPvWatts: Double?
    var solarBatteryVolts: Double?
    var solarBatteryAmps: Double?
    var inverterState = "—"
    var batterySOC: Double?
    var batteryState: BatteryActivity = .unknown
    var batteryVolts: Double?
    var batteryAmps: Double?
    var batteryWatts: Double?
    var batteryTimeToGo: Double?
    var acLoadAmps: Double?
    var dcSystemPower: Double?
    var dcLoadAmps: Double?

    static let sample = SystemSnapshot(
        gridAmps: 3.0,
        gridFromSystem: true,
        solarWatts: 0,
        inverterState: "Float charging",
        batterySOC: 100,
        batteryState: .charging,
        batteryVolts: 13.81,
        batteryAmps: 5.0,
        batteryWatts: 69,
        acLoadAmps: 0.6,
        dcSystemPower: 201.6,
        dcLoadAmps: 14.6
    )
}

struct SolarPoint: Codable, Equatable {
    var time: Date
    var watts: Double
}

struct SolarHourBar: Equatable, Identifiable {
    var hour: Int
    var wattHours: Double
    var id: Int { hour }
}

struct DeviceAlarm: Identifiable, Equatable {
    var id: String
    var title: String
    var level: String
}

enum ConsoleTab: String, CaseIterable, Identifiable {
    case brief, overview, levels, notifications, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief: return "Brief"
        case .overview: return "Overview"
        case .levels: return "Levels"
        case .notifications: return "Notifications"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .brief: return "scope"
        case .overview: return "rectangle.on.rectangle"
        case .levels: return "chart.bar.fill"
        case .notifications: return "bell.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var tab: ConsoleTab = .overview
    var settings: ConnectionSettings
    var password = ""
    var link: LinkState = .disconnected
    var snapshot = SystemSnapshot()
    var solarPoints: [SolarPoint] = []
    var alarms: [DeviceAlarm] = []
    var inverter = InverterControl()
    var shunt = ShuntDetail()
    var devicePage: GXDevice?
    var showSolar = false
    var showInverterControls = false
    var lastMessageAt: Date?
    var usingPreviewData = false

    private let mqtt = MQTTClient()
    private var keepAliveTask: Task<Void, Never>?
    private var didStart = false
    private var gridFromSystem = false

    init() {
        settings = Self.loadSettings()
        let stored = KeychainPassword.load()
        password = stored.isEmpty ? ConnectionSettings.defaultPassword : stored
        if stored.isEmpty {
            KeychainPassword.save(password)
        }
        solarPoints = Self.loadSolar()
    }

    var isLive: Bool {
        if case .connected = link { return true }
        return false
    }

    var statusText: String {
        switch link {
        case .disconnected:
            return "Not connected"
        case .connecting:
            return "Connecting to \(settings.host)…"
        case .connected:
            return "Connected"
        case .failed(let message):
            return message
        }
    }

    var needsPassword: Bool {
        settings.useTLS && password.isEmpty && !usingPreviewData
    }

    var solarBars: [Double] {
        Self.bars(from: solarPoints, count: 14, bucket: 15 * 60)
    }

    var solarHours: [SolarHourBar] {
        Self.hourlyYield(from: solarPoints)
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        if ProcessInfo.processInfo.arguments.contains("-previewData") {
            showPreviewData()
            return
        }
        mqtt.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        connect()
    }

    func connect() {
        usingPreviewData = false
        keepAliveTask?.cancel()
        guard !settings.host.isEmpty, !settings.portalID.isEmpty else {
            link = .failed("Enter the Cerbo address and VRM portal ID.")
            return
        }
        if settings.useTLS && password.isEmpty {
            mqtt.stop()
            link = .failed("Enter the Cerbo network password. This GX rejects anonymous MQTT.")
            return
        }
        link = .connecting
        mqtt.start(MQTTClient.Configuration(
            host: settings.host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: settings.port,
            useTLS: settings.useTLS,
            username: settings.username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        ))
    }

    func applyAndConnect(host: String, port: UInt16, useTLS: Bool, username: String, password: String, portalID: String) {
        settings = ConnectionSettings(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            useTLS: useTLS,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            portalID: portalID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        self.password = password
        Self.saveSettings(settings)
        KeychainPassword.save(password)
        snapshot = SystemSnapshot()
        inverter = InverterControl()
        shunt = ShuntDetail()
        alarms = []
        gridFromSystem = false
        connect()
        tab = .overview
    }

    func reconnectIfNeeded() {
        guard didStart, !usingPreviewData else { return }
        if case .connected = link { return }
        if case .connecting = link { return }
        connect()
    }

    func showPreviewData() {
        usingPreviewData = true
        mqtt.stop()
        link = .connected
        snapshot = .sample
        snapshot.solarName = "Solar MPPT"
        snapshot.solarState = 4
        snapshot.solarYieldKWh = 0.9
        snapshot.solarPvVolts = 39.69
        snapshot.solarPvWatts = 0
        snapshot.solarBatteryVolts = 14.35
        snapshot.solarBatteryAmps = 0
        inverter = .sample
        gridFromSystem = true
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let hourNow = calendar.component(.hour, from: now)
        var points: [SolarPoint] = []
        if hourNow >= 6 {
            for hour in 6...hourNow {
                let rise = sin(Double(hour - 6) / 10 * .pi)
                let watts = max(0, rise) * 720
                if let stamp = calendar.date(byAdding: .hour, value: hour, to: start) {
                    points.append(SolarPoint(time: stamp.addingTimeInterval(15 * 60), watts: watts))
                    points.append(SolarPoint(time: stamp.addingTimeInterval(45 * 60), watts: watts * 0.92))
                }
            }
        }
        solarPoints = points
    }

    private func handle(_ event: MQTTClient.Event) {
        switch event {
        case .state(let state):
            link = state
            if case .connected = state {
                armSubscriptions()
            } else {
                keepAliveTask?.cancel()
            }
        case .messages(let messages):
            var touched = false
            for (topic, payload) in messages {
                if apply(topic: topic, payload: payload) {
                    touched = true
                }
            }
            if touched {
                lastMessageAt = Date()
                recomputeDCLoad()
            }
        }
    }

    private func armSubscriptions() {
        let id = settings.portalID
        mqtt.subscribe(topic: "N/\(id)/#")
        mqtt.publish(topic: "R/\(id)/keepalive", payload: Data())
        mqtt.publish(topic: "R/\(id)/system/0/Serial", payload: Data())
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                let portal = self.settings.portalID
                let payload = Data(#"{"keepalive-options":["suppress-republish"]}"#.utf8)
                self.mqtt.publish(topic: "R/\(portal)/keepalive", payload: payload)
                self.mqtt.publish(topic: "R/\(portal)/system/0/Serial", payload: Data())
                self.mqtt.ping()
            }
        }
    }

    @discardableResult
    private func apply(topic: String, payload: Data) -> Bool {
        let parts = topic.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[0] == "N", parts[1].caseInsensitiveCompare(settings.portalID) == .orderedSame else {
            return false
        }
        let service = parts[2]
        let instance = parts[3]
        let path = parts.dropFirst(4).joined(separator: "/")
        let value = VenusValue.parse(payload)

        if path.contains("/Alarms/") || path.contains("/Warnings/") {
            updateAlarm(path: path, value: value)
        }

        switch (service, path) {
        case ("system", "Dc/Pv/Power"):
            if let watts = value.number {
                snapshot.solarWatts = watts
                recordSolar(watts)
            }
        case ("solarcharger", "CustomName"):
            if let text = value.text, !text.isEmpty { snapshot.solarName = text }
        case ("solarcharger", "State"):
            snapshot.solarState = value.number.map { Int($0.rounded()) }
        case ("solarcharger", "Pv/V"):
            snapshot.solarPvVolts = value.number
        case ("solarcharger", "Yield/Power"):
            snapshot.solarPvWatts = value.number
            if let watts = value.number {
                snapshot.solarWatts = watts
                recordSolar(watts)
            }
        case ("solarcharger", "Dc/0/Voltage"):
            snapshot.solarBatteryVolts = value.number
        case ("solarcharger", "Dc/0/Current"):
            snapshot.solarBatteryAmps = value.number
        case ("solarcharger", "History/Daily/0/Yield"):
            snapshot.solarYieldKWh = value.number
        case ("system", "Dc/Battery/Soc"):
            snapshot.batterySOC = value.number
        case ("system", "Dc/Battery/State"):
            snapshot.batteryState = BatteryActivity(code: value.number)
        case ("system", "Dc/Battery/Voltage"):
            snapshot.batteryVolts = value.number
        case ("system", "Dc/Battery/Current"):
            snapshot.batteryAmps = value.number
        case ("system", "Dc/Battery/Power"):
            snapshot.batteryWatts = value.number
        case ("system", "Dc/Battery/TimeToGo"):
            snapshot.batteryTimeToGo = value.number
            shunt.timeToGo = value.number
        case ("system", "Ac/Consumption/L1/Current"):
            snapshot.acLoadAmps = value.number
        case ("system", "Dc/System/Current"):
            if let amps = value.number {
                snapshot.dcLoadAmps = amps
            }
        case ("system", "Dc/System/Power"):
            snapshot.dcSystemPower = value.number
        case ("system", "Ac/Grid/L1/Current"):
            snapshot.gridAmps = value.number
            snapshot.gridFromSystem = true
            gridFromSystem = true
        case ("grid", "Ac/L1/Current"):
            if !gridFromSystem {
                snapshot.gridAmps = value.number
            }
        case ("vebus", "State"):
            snapshot.inverterState = inverterTitle(value.number)
            inverter.instance = instance
        case ("vebus", "CustomName"):
            if let text = value.text, !text.isEmpty {
                inverter.name = text
            }
            inverter.instance = instance
        case ("vebus", "Mode"):
            inverter.mode = value.number.map { Int($0.rounded()) }
            inverter.instance = instance
        case ("vebus", "ModeIsAdjustable"):
            inverter.modeAdjustable = (value.number ?? 1) != 0
        case ("vebus", "Ac/ActiveIn/CurrentLimit"):
            if let amps = value.number { inverter.currentLimit = amps }
            if let min = value.min { inverter.limitMin = min }
            if let max = value.max { inverter.limitMax = max }
            inverter.instance = instance
        case ("vebus", "Ac/ActiveIn/CurrentLimitIsAdjustable"):
            inverter.limitAdjustable = (value.number ?? 1) != 0
        case ("vebus", "Ac/ActiveIn/ActiveInput"):
            if let input = value.number { inverter.activeInput = Int(input.rounded()) }
        case ("vebus", "Ac/NumberOfAcInputs"):
            if let count = value.number { inverter.inputCount = Int(count.rounded()) }
        case ("vebus", "Settings/SystemSetup/AcInput1"):
            if let kind = value.number { inverter.input1 = Int(kind.rounded()) }
        case ("vebus", "Settings/SystemSetup/AcInput2"):
            if let kind = value.number { inverter.input2 = Int(kind.rounded()) }
        default:
            if applyDevice(service: service, instance: instance, path: path, value: value) {
                return true
            }
            return path.contains("/Alarms/") || path.contains("/Warnings/")
        }
        return true
    }

    private func applyDevice(service: String, instance: String, path: String, value: VenusValue) -> Bool {
        if service == "battery" {
            shunt.instance = instance
            switch path {
            case "ProductName":
                if let text = value.text, !text.isEmpty { shunt.productName = text }
            case "Dc/0/Voltage": shunt.voltage = value.number
            case "Dc/0/Current": shunt.current = value.number
            case "Dc/0/Power": shunt.power = value.number
            case "Soc": shunt.soc = value.number
            case "Dc/1/Voltage": shunt.starterVoltage = value.number
            case "ConsumedAmphours": shunt.consumedAh = value.number
            case "TimeToGo":
                shunt.timeToGo = value.number
                snapshot.batteryTimeToGo = value.number
            case "Alarms/Alarm": shunt.alarm = value.number.map { Int($0.rounded()) }
            case "Serial": shunt.serial = value.text
            case "FirmwareVersion": shunt.firmware = value.number
            default:
                if path.hasPrefix("Alarms/"), let code = value.number {
                    shunt.alarms[String(path.dropFirst("Alarms/".count))] = Int(code.rounded())
                } else if path.hasPrefix("History/"), let number = value.number, !path.contains("Daily/") {
                    shunt.history[String(path.dropFirst("History/".count))] = number
                } else {
                    return false
                }
            }
            return true
        }
        guard service == "vebus" else { return false }
        switch path {
        case "Dc/0/Voltage": inverter.dcVoltage = value.number
        case "Dc/0/Current": inverter.dcCurrent = value.number
        case "Dc/0/Power": inverter.dcPower = value.number
        case "Soc": inverter.vebusSOC = value.number
        case "Ac/ActiveIn/L1/P": inverter.acInPower = value.number
        case "Ac/ActiveIn/L1/V": inverter.acInVolts = value.number
        case "Ac/ActiveIn/L1/I": inverter.acInAmps = value.number
        case "Ac/ActiveIn/L1/F": inverter.acInHz = value.number
        case "Ac/Out/L1/P": inverter.acOutPower = value.number
        case "Ac/Out/L1/V": inverter.acOutVolts = value.number
        case "Ac/Out/L1/I": inverter.acOutAmps = value.number
        case "Ac/Out/L1/F": inverter.acOutHz = value.number
        case "ProductName":
            if let text = value.text, !text.isEmpty { inverter.productName = text }
        case "Serial": inverter.serial = value.text
        case "FirmwareVersion": inverter.firmware = value.number
        default:
            if path.hasPrefix("Alarms/"), let code = value.number {
                inverter.alarms[String(path.dropFirst("Alarms/".count))] = Int(code.rounded())
            } else {
                return false
            }
        }
        inverter.instance = instance
        return true
    }

    func setInverterMode(_ mode: Int) {
        guard inverter.modeAdjustable else { return }
        inverter.mode = mode
        writeVEBus("Mode", value: Double(mode), wholeNumber: true)
    }

    func nudgeCurrentLimit(by step: Double) {
        guard inverter.limitAdjustable else { return }
        let current = inverter.currentLimit ?? inverter.limitMin
        let next = min(max(current + step, inverter.limitMin), inverter.limitMax)
        inverter.currentLimit = next
        writeVEBus("Ac/ActiveIn/CurrentLimit", value: next, wholeNumber: next.rounded() == next)
    }

    private func writeVEBus(_ path: String, value: Double, wholeNumber: Bool) {
        guard let instance = inverter.instance else { return }
        let rendered = wholeNumber ? String(Int(value.rounded())) : String(format: "%.1f", value)
        let topic = "W/\(settings.portalID)/vebus/\(instance)/\(path)"
        mqtt.publish(topic: topic, payload: Data("{\"value\":\(rendered)}".utf8))
    }

    private func recomputeDCLoad() {
        guard snapshot.dcLoadAmps == nil,
              let power = snapshot.dcSystemPower,
              let volts = snapshot.batteryVolts,
              volts > 1 else { return }
        snapshot.dcLoadAmps = power / volts
    }

    private func recordSolar(_ watts: Double) {
        let now = Date()
        if let last = solarPoints.last, now.timeIntervalSince(last.time) < 20 {
            solarPoints[solarPoints.count - 1] = SolarPoint(time: now, watts: watts)
            return
        } else {
            solarPoints.append(SolarPoint(time: now, watts: watts))
        }
        let cutoff = now.addingTimeInterval(-26 * 60 * 60)
        solarPoints.removeAll { $0.time < cutoff }
        if solarPoints.count > 5_200 {
            solarPoints.removeFirst(solarPoints.count - 5_200)
        }
        Self.saveSolar(solarPoints)
    }

    private func updateAlarm(path: String, value: VenusValue) {
        let code = Int(value.number ?? 0)
        if code <= 0 {
            alarms.removeAll { $0.id == path }
            return
        }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let alarm = DeviceAlarm(
            id: path,
            title: Self.pretty(name),
            level: code >= 2 ? "Alarm" : "Warning"
        )
        if let index = alarms.firstIndex(where: { $0.id == path }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
    }

    private func inverterTitle(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch Int(value.rounded()) {
        case 0: return "Off"
        case 1: return "Low power"
        case 2: return "Fault"
        case 3: return "Bulk charging"
        case 4: return "Absorption charging"
        case 5: return "Float charging"
        case 6: return "Storage"
        case 7: return "Equalize"
        case 8: return "Passthru"
        case 9: return "Inverting"
        case 10: return "Power assist"
        case 11: return "Power supply"
        case 252: return "External control"
        default: return "Unknown (\(Int(value.rounded())))"
        }
    }

    static func hourlyYield(from points: [SolarPoint], now: Date = Date()) -> [SolarHourBar] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let currentHour = calendar.component(.hour, from: now)
        var buckets = Array(repeating: 0.0, count: 24)
        let samples = points
            .filter { $0.time >= start && $0.time <= now }
            .sorted { $0.time < $1.time }
        for index in samples.indices {
            let sample = samples[index]
            let following = index + 1 < samples.count ? samples[index + 1].time : now
            let span = min(max(0, following.timeIntervalSince(sample.time)), 5 * 60)
            let hour = calendar.component(.hour, from: sample.time)
            guard hour >= 0, hour < 24 else { continue }
            buckets[hour] += sample.watts * span / 3_600
        }
        return (0...currentHour).map { SolarHourBar(hour: $0, wattHours: buckets[$0]) }
    }

    static func bars(from points: [SolarPoint], count: Int, bucket: TimeInterval, now: Date = Date()) -> [Double] {
        (0..<count).map { index in
            let slotEnd = now.addingTimeInterval(-Double(count - 1 - index) * bucket)
            let slotStart = slotEnd.addingTimeInterval(-bucket)
            let samples = points.filter { $0.time >= slotStart && $0.time < slotEnd + (index == count - 1 ? 1 : 0) }
            return samples.last?.watts ?? 0
        }
    }

    static func pretty(_ raw: String) -> String {
        var result = ""
        for character in raw {
            if character.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(character)
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    private static let settingsKey = "cerbo.connection"
    private static let solarKey = "cerbo.solar"

    private static func loadSettings() -> ConnectionSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let saved = try? JSONDecoder().decode(StoredSettings.self, from: data) else {
            return .device
        }
        return saved.settings
    }

    private static func saveSettings(_ settings: ConnectionSettings) {
        let data = try? JSONEncoder().encode(StoredSettings(settings: settings))
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    private static func loadSolar() -> [SolarPoint] {
        guard let data = UserDefaults.standard.data(forKey: solarKey),
              let points = try? JSONDecoder().decode([SolarPoint].self, from: data) else {
            return []
        }
        return points
    }

    private static func saveSolar(_ points: [SolarPoint]) {
        let data = try? JSONEncoder().encode(points)
        UserDefaults.standard.set(data, forKey: solarKey)
    }
}

private struct StoredSettings: Codable {
    var host: String
    var port: UInt16
    var useTLS: Bool
    var username: String
    var portalID: String

    init(settings: ConnectionSettings) {
        host = settings.host
        port = settings.port
        useTLS = settings.useTLS
        username = settings.username
        portalID = settings.portalID
    }

    var settings: ConnectionSettings {
        ConnectionSettings(host: host, port: port, useTLS: useTLS, username: username, portalID: portalID)
    }
}

private enum KeychainPassword {
    static let service = "CerboGX"
    static let account = "gx-password"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return ""
        }
        return password
    }

    static func save(_ password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum GXDevice: String, Identifiable {
    case inverter
    case shunt

    var id: String { rawValue }
}

struct ShuntDetail: Equatable {
    var instance: String?
    var productName = "SmartShunt"
    var voltage: Double?
    var current: Double?
    var power: Double?
    var soc: Double?
    var starterVoltage: Double?
    var consumedAh: Double?
    var timeToGo: Double?
    var alarm: Int?
    var serial: String?
    var firmware: Double?
    var alarms: [String: Int] = [:]
    var history: [String: Double] = [:]

    var summary: String {
        "\(DetailText.volts(voltage))  |  \(DetailText.signedAmps(current))  |  \(DetailText.signedWatts(power))"
    }
}

struct InverterControl: Equatable {
    var instance: String?
    var name = "Inverter"
    var mode: Int?
    var modeAdjustable = true
    var currentLimit: Double?
    var limitMin = 0.0
    var limitMax = 50.0
    var limitAdjustable = true
    var activeInput = 0
    var inputCount = 1
    var input1 = 1
    var input2 = 0
    var dcVoltage: Double?
    var dcCurrent: Double?
    var dcPower: Double?
    var vebusSOC: Double?
    var acInPower: Double?
    var acInVolts: Double?
    var acInAmps: Double?
    var acInHz: Double?
    var acOutPower: Double?
    var acOutVolts: Double?
    var acOutAmps: Double?
    var acOutHz: Double?
    var productName = ""
    var serial: String?
    var firmware: Double?
    var alarms: [String: Int] = [:]

    var inputTitle: String {
        let kind = activeInput == 0 ? input1 : input2
        switch kind {
        case 2: return "Generator"
        case 3: return "Shore"
        default: return "Grid"
        }
    }

    var limitText: String {
        guard let currentLimit else { return "— A" }
        if currentLimit.rounded() == currentLimit {
            return "\(Int(currentLimit)) A"
        }
        return String(format: "%.1f A", currentLimit)
    }

    var limitButtonText: String {
        guard let currentLimit else { return "—" }
        return String(format: "%.1fA", currentLimit)
    }

    var modeTitle: String {
        switch mode {
        case 1: return "Charger only"
        case 2: return "Inverter only"
        case 3: return "On"
        case 4: return "Off"
        default: return "—"
        }
    }

    var activeInputTitle: String {
        "AC input \(activeInput + 1)"
    }

    static let modes: [(code: Int, title: String)] = [
        (3, "On"),
        (1, "Charger only"),
        (2, "Inverter only"),
        (4, "Off")
    ]

    static let sample = InverterControl(
        instance: "276",
        name: "PVRV",
        mode: 3,
        currentLimit: 50,
        limitMax: 50,
        input1: 1
    )
}

private struct VenusValue {
    var number: Double?
    var text: String?
    var min: Double?
    var max: Double?

    static func parse(_ data: Data) -> VenusValue {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return VenusValue()
        }
        var parsed = VenusValue()
        let raw: Any?
        if let dictionary = object as? [String: Any] {
            raw = dictionary["value"]
            parsed.min = (dictionary["min"] as? NSNumber)?.doubleValue
            parsed.max = (dictionary["max"] as? NSNumber)?.doubleValue
        } else {
            raw = object
        }
        guard let raw, !(raw is NSNull) else { return parsed }
        if let text = raw as? String {
            parsed.text = text
            parsed.number = Double(text)
        } else if let number = raw as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                parsed.number = number.boolValue ? 1 : 0
            } else {
                parsed.number = number.doubleValue
            }
        }
        return parsed
    }
}

private extension BatteryActivity {
    init(code: Double?) {
        switch Int(code?.rounded() ?? -1) {
        case 0: self = .idle
        case 1: self = .charging
        case 2: self = .discharging
        default: self = .unknown
        }
    }
}

enum MetricFormat {
    static func acLoadValue(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return -abs(value)
    }

    static func amps(_ value: Double?, plusWhenPositive: Bool = false) -> String {
        guard let value else { return "—" }
        let prefix = plusWhenPositive && value > 0 ? "+" : ""
        return String(format: "%@%.1fA", prefix, value)
    }

    static func gridTile(_ amps: Double?) -> String {
        guard let amps else { return "Disconnected" }
        return String(format: "%.1fA", amps)
    }

    static func acLoadAmps(_ value: Double?) -> String {
        amps(acLoadValue(value))
    }

    static func acLoadAmpsText(_ value: Double?) -> String {
        ampsText(acLoadValue(value))
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))w"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) %"
    }

    static func voltsText(_ value: Double?) -> String {
        guard let value else { return "— V" }
        return String(format: "%.2f V", value)
    }

    static func ampsText(_ value: Double?, plusWhenPositive: Bool = false) -> String {
        guard let value else { return "— A" }
        let prefix = plusWhenPositive && value > 0 ? "+" : ""
        return String(format: "%@%.1f A", prefix, value)
    }

    static func wattsText(_ value: Double?, plusWhenPositive: Bool = false) -> String {
        guard let value else { return "— w" }
        let prefix = plusWhenPositive && value > 0 ? "+" : ""
        return "\(prefix)\(Int(value.rounded())) w"
    }

    static func yield(_ kilowattHours: Double?) -> String {
        guard let kilowattHours else { return "—" }
        let wattHours = kilowattHours * 1_000
        if wattHours < 1_000 {
            return "\(Int(wattHours.rounded())) Wh"
        }
        return String(format: "%.2f kWh", kilowattHours)
    }

    static func pvVolts(_ value: Double?) -> String {
        guard let value else { return "— V" }
        return String(format: "%.2f V", value)
    }

    static func pvCurrent(watts: Double?, volts: Double?) -> String {
        guard let watts, watts > 1, let volts, volts > 1 else { return "-- A" }
        let current = watts / volts
        let prefix = current > 0 ? "+" : ""
        return String(format: "%@%.1f A", prefix, current)
    }

    static func mpptState(_ code: Int?) -> String {
        switch code {
        case 0: return "Off"
        case 1: return "Low power"
        case 2: return "Fault"
        case 3: return "Bulk"
        case 4: return "Absorption"
        case 5: return "Float"
        case 6: return "Storage"
        case 7: return "Equalize"
        case 11: return "Wake-up"
        case 245: return "External control"
        default: return "—"
        }
    }

    static func hourLabel(_ hour: Int) -> String {
        let wrapped = hour % 12
        let shown = wrapped == 0 ? 12 : wrapped
        return "\(shown)\(hour < 12 ? "a" : "p")"
    }
}
