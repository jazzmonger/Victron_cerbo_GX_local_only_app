import SwiftUI
import UIKit

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesPadLayout: Bool {
        AdaptiveLayout.usesPadConsole(horizontalSizeClass)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if usesPadLayout {
                HStack(spacing: 0) {
                    padSidebar
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                    VStack(spacing: 0) {
                        header
                        tabContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    header
                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    tabBar
                }
            }
        }
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.reconnectIfNeeded()
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.devicePage != nil || model.showSolar },
            set: { presented in
                if !presented {
                    model.devicePage = nil
                    model.showSolar = false
                }
            }
        )) {
            if model.showSolar {
                SolarHistoryView(model: model)
            } else {
                DeviceBrowserView(model: model)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch model.tab {
            case .brief:
                BriefView(model: model)
            case .overview:
                OverviewView(model: model)
            case .levels:
                LevelsView(model: model)
            case .notifications:
                NotificationsView(model: model)
            case .settings:
                SettingsView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, usesPadLayout ? 16 : 0)
    }

    private var padSidebar: some View {
        VStack(spacing: 6) {
            ForEach(ConsoleTab.allCases) { tab in
                Button {
                    model.tab = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 22, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(model.tab == tab ? Theme.tabOn : Theme.tabOff)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        model.tab == tab ? Color.white.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .frame(width: AdaptiveLayout.padSidebarWidth)
        .background(Color(white: 0.07))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: usesPadLayout ? 10 : 8, height: usesPadLayout ? 10 : 8)
            Text("Remote console")
                .font(.system(size: usesPadLayout ? 22 : 17, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, usesPadLayout ? 24 : 16)
        .padding(.top, usesPadLayout ? 12 : 6)
        .padding(.bottom, usesPadLayout ? 14 : 10)
    }

    private var dotColor: Color {
        switch model.link {
        case .connected: return Color(red: 0.35, green: 0.82, blue: 0.45)
        case .connecting: return Color(red: 0.95, green: 0.78, blue: 0.25)
        case .failed: return Theme.brightRed
        case .disconnected: return Color(white: 0.45)
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(ConsoleTab.allCases) { tab in
                    Button {
                        model.tab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(model.tab == tab ? Theme.tabOn : Theme.tabOff)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.black)
    }
}

struct BriefView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                briefCard {
                    HStack {
                        Image(systemName: "sun.max")
                        Text("Solar")
                        Spacer()
                        Text(MetricFormat.watts(model.snapshot.solarWatts))
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Theme.signColor(model.snapshot.solarWatts))
                            .monospacedDigit()
                    }
                }
                .onTapGesture { model.showSolar = true }

                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.bolt)

                briefCard(chargeFraction: briefBatteryFill) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "battery.100")
                            Text("Battery")
                            Spacer()
                            Text(model.snapshot.batteryState.title)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Text(MetricFormat.percent(model.snapshot.batterySOC))
                            .font(.system(size: 48, weight: .medium))
                            .monospacedDigit()
                        Text(DetailText.timeToGo(model.snapshot.batteryTimeToGo))
                            .font(.system(size: 16, weight: .medium))
                            .monospacedDigit()
                        HStack(spacing: 8) {
                            Text(MetricFormat.voltsText(model.snapshot.batteryVolts))
                            Text(MetricFormat.ampsText(model.snapshot.batteryAmps))
                                .foregroundStyle(Theme.signColor(model.snapshot.batteryAmps))
                            Text(MetricFormat.wattsText(model.snapshot.batteryWatts))
                                .foregroundStyle(Theme.signColor(model.snapshot.batteryWatts))
                        }
                        .font(.system(size: 15, weight: .medium))
                        .monospacedDigit()
                    }
                }
                .onTapGesture { model.devicePage = .shunt }

                HStack(spacing: 12) {
                    metricBlock(title: "Grid", value: MetricFormat.amps(model.snapshot.gridAmps), sign: model.snapshot.gridAmps, symbol: "powerplug")
                    metricBlock(title: "Inverter", value: model.snapshot.inverterState, symbol: "arrow.left.arrow.right.square")
                        .onTapGesture { model.devicePage = .inverter }
                }
                HStack(spacing: 12) {
                    metricBlock(title: "AC Loads", value: MetricFormat.acLoadAmps(model.snapshot.acLoadAmps), sign: MetricFormat.acLoadValue(model.snapshot.acLoadAmps), symbol: "arrow.triangle.2.circlepath")
                    metricBlock(title: "DC Loads", value: MetricFormat.amps(model.snapshot.dcLoadAmps), sign: model.snapshot.dcLoadAmps, symbol: "circle.grid.cross")
                }
            }
            .padding(16)
        }
    }

    private var briefBatteryFill: Double {
        guard let soc = model.snapshot.batterySOC else { return 0 }
        return min(1, max(0, soc / 100))
    }

    private func briefCard<Content: View>(chargeFraction: Double? = nil, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ChargeFill(fraction: chargeFraction ?? 0, showsCharge: chargeFraction != nil)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            }
    }

    private func metricBlock(title: String, value: String, sign: Double? = nil, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.signColor(sign))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
    }
}

struct LevelsView: View {
    var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                section("Battery", rows: [
                    ("State of charge", MetricFormat.percent(model.snapshot.batterySOC), nil),
                    ("State", model.snapshot.batteryState.title, nil),
                    ("Voltage", MetricFormat.voltsText(model.snapshot.batteryVolts), nil),
                    ("Current", MetricFormat.ampsText(model.snapshot.batteryAmps), model.snapshot.batteryAmps),
                    ("Power", MetricFormat.wattsText(model.snapshot.batteryWatts), model.snapshot.batteryWatts),
                    ("Time-to-go", DetailText.timeToGo(model.snapshot.batteryTimeToGo), nil)
                ])
                section("Solar", rows: [
                    ("PV power", MetricFormat.wattsText(model.snapshot.solarWatts), model.snapshot.solarWatts)
                ])
                section("AC", rows: [
                    ("Grid current", MetricFormat.ampsText(model.snapshot.gridAmps), model.snapshot.gridAmps),
                    ("AC load current", MetricFormat.acLoadAmpsText(model.snapshot.acLoadAmps), MetricFormat.acLoadValue(model.snapshot.acLoadAmps)),
                    ("Inverter / charger", model.snapshot.inverterState, nil)
                ])
                section("DC", rows: [
                    ("DC load current", MetricFormat.ampsText(model.snapshot.dcLoadAmps), model.snapshot.dcLoadAmps),
                    ("DC system power", MetricFormat.wattsText(model.snapshot.dcSystemPower), model.snapshot.dcSystemPower)
                ])
            }
            .padding(16)
        }
    }

    private func section(_ title: String, rows: [(String, String, Double?)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(row.0)
                        Spacer()
                        Text(row.1)
                            .monospacedDigit()
                            .foregroundStyle(row.2.map { Theme.signColor($0) } ?? Color.white.opacity(0.85))
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct NotificationsView: View {
    var model: AppModel

    var body: some View {
        Group {
            if model.alarms.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("No notifications")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.alarms) { alarm in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: alarm.level == "Alarm" ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(alarm.level == "Alarm" ? Theme.brightRed : Color.yellow)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(alarm.title)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(alarm.level)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var host = ""
    @State private var port = ""
    @State private var useTLS = true
    @State private var username = ""
    @State private var password = ""
    @State private var portalID = ""
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This Cerbo uses a network password. It is the same password as the remote console login at \(host.isEmpty ? "the GX address" : host). Anonymous MQTT on port 1883 is refused.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                field("Cerbo address", text: $host, keyboard: .numbersAndPunctuation)
                field("VRM Portal ID", text: $portalID)
                field("Username", text: $username)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    SecureField("Network password", text: $password)
                        .textContentType(.password)
                        .padding(12)
                        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Toggle(isOn: $useTLS) {
                    Text("Secure connection (TLS)")
                        .foregroundStyle(.white)
                }
                .tint(Theme.tabOn)
                .onChange(of: useTLS) { _, enabled in
                    if enabled, port == "1883" { port = "8883" }
                    if !enabled, port == "8883" { port = "1883" }
                }

                field("Port", text: $port, keyboard: .numberPad)

                Button(action: save) {
                    Text("Connect")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.tabOn, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    statusRow("Connection status", model.statusText)
                    statusRow("Last update", lastUpdate)
                    statusRow("Portal ID", model.settings.portalID)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(16)
        }
        .onAppear(perform: load)
        .scrollDismissesKeyboard(.interactively)
    }

    private var lastUpdate: String {
        guard let date = model.lastMessageAt else { return "Waiting for data" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 2 { return "Just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m \(seconds % 60)s ago"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        host = model.settings.host
        port = String(model.settings.port)
        useTLS = model.settings.useTLS
        username = model.settings.username
        password = model.password
        portalID = model.settings.portalID
    }

    private func save() {
        let parsedPort = UInt16(port) ?? (useTLS ? 8883 : 1883)
        model.applyAndConnect(
            host: host,
            port: parsedPort,
            useTLS: useTLS,
            username: username.isEmpty ? "remoteconsole" : username,
            password: password,
            portalID: portalID
        )
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .padding(12)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
        }
        .font(.system(size: 14))
    }
}

struct InverterControlsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingLimit = false

    var body: some View {
        ZStack {
            Color(white: 0.14).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    Text("Controls")
                        .font(.system(size: 34, weight: .regular))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 36, height: 36)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                }

                controlCard
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .foregroundStyle(.white)
        }
        .sheet(isPresented: $editingLimit) {
            CurrentLimitSheet(model: model)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 16, weight: .medium))
                Text(model.inverter.name)
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text(model.inverter.inputTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
            }

            HStack {
                Text("\(model.inverter.inputTitle) current limit:")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 8)
                Button {
                    editingLimit = true
                } label: {
                    Text(model.inverter.limitText)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Color(red: 0.18, green: 0.47, blue: 0.95),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.inverter.limitAdjustable)
            }

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)

            Text("Mode")
                .font(.system(size: 20, weight: .semibold))

            VStack(spacing: 14) {
                ForEach(InverterControl.modes, id: \.code) { mode in
                    Button {
                        model.setInverterMode(mode.code)
                    } label: {
                        HStack {
                            Text(mode.title)
                                .font(.system(size: 17))
                            Spacer()
                            ModeRadio(selected: model.inverter.mode == mode.code)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.inverter.modeAdjustable)
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ModeRadio: View {
    var selected: Bool

    var body: some View {
        Circle()
            .strokeBorder(selected ? Color(red: 0.25, green: 0.55, blue: 0.98) : Color.white.opacity(0.55), lineWidth: 2)
            .background {
                if selected {
                    Circle()
                        .fill(Color(red: 0.25, green: 0.55, blue: 0.98))
                        .padding(5)
                }
            }
            .frame(width: 22, height: 22)
    }
}

struct CurrentLimitSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Text("\(model.inverter.inputTitle) current limit")
                .font(.headline)
            Text(model.inverter.limitText)
                .font(.system(size: 44, weight: .medium))
                .monospacedDigit()
            HStack(spacing: 28) {
                limitButton("minus") { model.nudgeCurrentLimit(by: -1) }
                limitButton("plus") { model.nudgeCurrentLimit(by: 1) }
            }
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.14))
        .foregroundStyle(.white)
    }

    private func limitButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 64, height: 48)
                .background(Color(red: 0.18, green: 0.47, blue: 0.95), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
