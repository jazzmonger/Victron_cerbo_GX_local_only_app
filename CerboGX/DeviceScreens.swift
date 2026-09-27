import SwiftUI

enum DeviceSection: Hashable {
    case shuntAlarms
    case shuntHistory
    case shuntDevice
    case inverterAdvanced
    case inverterAlarmStatus
    case inverterAlarmSetup

    var title: String {
        switch self {
        case .shuntAlarms: return "Alarms"
        case .shuntHistory: return "History"
        case .shuntDevice: return "Device"
        case .inverterAdvanced: return "Advanced"
        case .inverterAlarmStatus: return "Alarm status"
        case .inverterAlarmSetup: return "Alarm setup"
        }
    }
}

struct DeviceBrowserView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showMode = false
    @State private var showLimit = false

    private var page: GXDevice { model.devicePage ?? .inverter }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                tabStrip
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 8) {
                        if page == .shunt {
                            shuntRows
                        } else {
                            inverterRows
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DeviceSection.self) { section in
                DeviceSectionPage(section: section, model: model)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMode) {
            InverterControlsView(model: model)
        }
        .sheet(isPresented: $showLimit) {
            CurrentLimitSheet(model: model)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        ZStack {
            Menu {
                Button(model.inverter.name) { model.devicePage = .inverter }
                Button(model.shunt.productName) { model.devicePage = .shunt }
            } label: {
                HStack(spacing: 4) {
                    Text(model.inverter.name)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            }
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var tabStrip: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 34)
                    .background(Color(red: 0.10, green: 0.18, blue: 0.30), in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                dismiss()
            } label: {
                Text("Overview")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color(red: 0.10, green: 0.18, blue: 0.30), in: Capsule())
            }
            .buttonStyle(.plain)
            Text(page == .shunt ? model.shunt.productName : model.inverter.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color(red: 0.22, green: 0.55, blue: 0.95), in: Capsule())
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var shuntRows: some View {
        DeviceRow(title: "Battery", value: model.shunt.summary)
        DeviceRow(title: "State of charge", value: DetailText.percent(model.shunt.soc))
        DeviceRow(title: "Starter voltage", value: DetailText.volts(model.shunt.starterVoltage))
        DeviceRow(title: "Consumed AmpHours", value: DetailText.ampHours(model.shunt.consumedAh))
        DeviceRow(title: "Time-to-go", value: DetailText.timeToGo(model.shunt.timeToGo))
        DeviceRow(title: "Alarm state", value: DetailText.alarm(model.shunt.alarm))
        NavigationLink(value: DeviceSection.shuntAlarms) {
            DeviceRow(title: "Alarms", chevron: true)
        }
        .buttonStyle(.plain)
        NavigationLink(value: DeviceSection.shuntHistory) {
            DeviceRow(title: "History", chevron: true)
        }
        .buttonStyle(.plain)
        NavigationLink(value: DeviceSection.shuntDevice) {
            DeviceRow(title: "Device", chevron: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var inverterRows: some View {
        DeviceRow(title: "Mode") {
            outlineButton(model.inverter.modeTitle) { showMode = true }
        }
        DeviceRow(title: "State", value: model.snapshot.inverterState)
        DeviceRow(title: "\(model.inverter.inputTitle) current limit") {
            outlineButton(model.inverter.limitButtonText) { showLimit = true }
        }
        DeviceRow(title: "DC Voltage", value: DetailText.volts(model.inverter.dcVoltage))
        DeviceRow(title: "DC Current", value: DetailText.signedAmps(model.inverter.dcCurrent))
        DeviceRow(title: "State of charge", value: DetailText.percent(model.inverter.vebusSOC))
        DeviceRow(title: "Active AC Input", value: model.inverter.activeInputTitle)
        DeviceRow(
            title: "AC In",
            value: DetailText.ac(
                power: model.inverter.acInPower,
                volts: model.inverter.acInVolts,
                amps: model.inverter.acInAmps,
                hz: model.inverter.acInHz
            )
        )
        DeviceRow(
            title: "AC Out",
            value: DetailText.ac(
                power: model.inverter.acOutPower,
                volts: model.inverter.acOutVolts,
                amps: model.inverter.acOutAmps,
                hz: model.inverter.acOutHz
            )
        )
        NavigationLink(value: DeviceSection.inverterAdvanced) {
            DeviceRow(title: "Advanced", chevron: true)
        }
        .buttonStyle(.plain)
        NavigationLink(value: DeviceSection.inverterAlarmStatus) {
            DeviceRow(title: "Alarm status", chevron: true)
        }
        .buttonStyle(.plain)
        NavigationLink(value: DeviceSection.inverterAlarmSetup) {
            DeviceRow(title: "Alarm setup", chevron: true)
        }
        .buttonStyle(.plain)
    }

    private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(red: 0.28, green: 0.58, blue: 0.98), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
    }
}

struct DeviceSectionPage: View {
    var section: DeviceSection
    var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                rows
            }
            .padding(12)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var rows: some View {
        switch section {
        case .shuntAlarms:
            alarmRows(model.shunt.alarms)
        case .shuntHistory:
            historyRows
        case .shuntDevice:
            DeviceRow(title: "Product", value: model.shunt.productName)
            DeviceRow(title: "Serial number", value: model.shunt.serial ?? "—")
            DeviceRow(title: "Firmware", value: DetailText.firmware(model.shunt.firmware))
        case .inverterAdvanced:
            DeviceRow(title: "Product", value: model.inverter.productName.isEmpty ? "—" : model.inverter.productName)
            DeviceRow(title: "Serial number", value: model.inverter.serial ?? "—")
            DeviceRow(title: "Firmware", value: DetailText.firmware(model.inverter.firmware))
            DeviceRow(title: "DC power", value: DetailText.signedWatts(model.inverter.dcPower))
            DeviceRow(title: "AC inputs", value: "\(model.inverter.inputCount)")
            DeviceRow(title: "Active input", value: model.inverter.inputTitle)
        case .inverterAlarmStatus:
            alarmRows(model.inverter.alarms)
        case .inverterAlarmSetup:
            if model.inverter.alarms.isEmpty {
                DeviceRow(title: "Alarm setup", value: "No settings reported")
            } else {
                ForEach(model.inverter.alarms.keys.sorted(), id: \.self) { key in
                    DeviceRow(title: AppModel.pretty(key), value: DetailText.alarm(model.inverter.alarms[key]))
                }
            }
        }
    }

    @ViewBuilder
    private func alarmRows(_ alarms: [String: Int]) -> some View {
        let active = alarms.filter { $0.value > 0 }
        if alarms.isEmpty {
            DeviceRow(title: "Alarms", value: "None reported")
        } else if active.isEmpty {
            DeviceRow(title: "Status", value: "OK")
            ForEach(alarms.keys.sorted(), id: \.self) { key in
                DeviceRow(title: AppModel.pretty(key), value: "OK")
            }
        } else {
            ForEach(alarms.keys.sorted(), id: \.self) { key in
                DeviceRow(title: AppModel.pretty(key), value: DetailText.alarm(alarms[key]))
            }
        }
    }

    @ViewBuilder
    private var historyRows: some View {
        let history = model.shunt.history
        if history.isEmpty {
            DeviceRow(title: "History", value: "None reported")
        } else {
            ForEach(Self.historyFields, id: \.key) { field in
                if let value = history[field.key] {
                    DeviceRow(title: field.title, value: field.format(value))
                }
            }
        }
    }

    private static let historyFields: [(key: String, title: String, format: (Double) -> String)] = [
        ("DeepestDischarge", "Deepest discharge", { DetailText.ampHours($0) }),
        ("LastDischarge", "Last discharge", { DetailText.ampHours($0) }),
        ("AverageDischarge", "Average discharge", { DetailText.ampHours($0) }),
        ("ChargeCycles", "Charge cycles", { "\(Int($0.rounded()))" }),
        ("FullDischarges", "Full discharges", { "\(Int($0.rounded()))" }),
        ("TotalAhDrawn", "Total Ah drawn", { DetailText.ampHours($0) }),
        ("MinimumVoltage", "Minimum voltage", { DetailText.volts($0) }),
        ("MaximumVoltage", "Maximum voltage", { DetailText.volts($0) }),
        ("MinimumStarterVoltage", "Minimum starter voltage", { DetailText.volts($0) }),
        ("MaximumStarterVoltage", "Maximum starter voltage", { DetailText.volts($0) }),
        ("TimeSinceLastFullCharge", "Time since last full charge", { DetailText.elapsed($0) }),
        ("AutomaticSyncs", "Automatic synchronizations", { "\(Int($0.rounded()))" }),
        ("DischargedEnergy", "Discharged energy", { String(format: "%.1f kWh", $0) }),
        ("ChargedEnergy", "Charged energy", { String(format: "%.1f kWh", $0) })
    ]
}

struct DeviceRow<Accessory: View>: View {
    var title: String
    var value: String?
    var chevron: Bool
    @ViewBuilder var accessory: () -> Accessory

    init(title: String, value: String? = nil, chevron: Bool = false, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.value = value
        self.chevron = chevron
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            accessory()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension DeviceRow where Accessory == EmptyView {
    init(title: String, value: String? = nil, chevron: Bool = false) {
        self.init(title: title, value: value, chevron: chevron) { EmptyView() }
    }
}

enum DetailText {
    static func volts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f V", value)
    }

    static func signedAmps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f A", value)
    }

    static func signedWatts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) W"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "-- %" }
        return "\(Int(value.rounded())) %"
    }

    static func ampHours(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f Ah", value)
    }

    /// Victron leaves TimeToGo null while charging or idle, and caps it at 864000 seconds (10 days) when it is not a real countdown. Both show as infinity.
    static func timeToGo(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < 864_000 else { return "∞" }
        return compactDuration(seconds)
    }

    static func elapsed(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        return compactDuration(seconds)
    }

    private static func compactDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func alarm(_ code: Int?) -> String {
        switch code {
        case 0: return "OK"
        case 1: return "Warning"
        case 2: return "Alarm"
        default: return "—"
        }
    }

    static func firmware(_ value: Double?) -> String {
        guard let value else { return "—" }
        let code = Int(value.rounded())
        let major = code >> 8
        let minor = code & 0xFF
        if major > 0, major < 30 {
            return String(format: "v%d.%02d", major, minor)
        }
        return "\(code)"
    }

    static func ac(power: Double?, volts: Double?, amps: Double?, hz: Double?) -> String {
        let watts = power.map { "\(Int($0.rounded())) W" } ?? "—"
        let voltage = volts.map { "\(Int($0.rounded())) V" } ?? "—"
        let current = amps.map { String(format: "%.1f A", $0) } ?? "—"
        let frequency = hz.map { String(format: "%.1f Hz", $0) } ?? "—"
        return "\(watts)  |  \(voltage)  |  \(current)  |  \(frequency)"
    }
}
