import SwiftUI

enum Theme {
    static let card = Color(red: 0.051, green: 0.133, blue: 0.220)
    static let cardStroke = Color(red: 0.18, green: 0.36, blue: 0.55).opacity(0.45)
    static let batteryTop = Color(red: 0.29, green: 0.60, blue: 0.88)
    static let batteryBottom = Color(red: 0.16, green: 0.45, blue: 0.76)
    static let bar = Color(red: 0.45, green: 0.72, blue: 0.96)
    static let barLow = Color(red: 0.28, green: 0.50, blue: 0.74)
    static let bolt = Color(red: 0.40, green: 0.70, blue: 0.98)
    static let tabOn = Color(red: 0.35, green: 0.66, blue: 0.98)
    static let tabOff = Color(white: 0.56)
    static let label = Color.white.opacity(0.92)
    static let charge = Color(red: 0.98, green: 0.82, blue: 0.22)
    /// Bright red for discharge and emphasis (battery tile stats, negative amps/watts).
    static let brightRed = Color(red: 1.0, green: 0.12, blue: 0.08)
    static let discharge = brightRed

    static func signColor(_ value: Double?) -> Color {
        guard let value, value > 0 else { return .white }
        return charge
    }

    static var batteryGradient: LinearGradient {
        LinearGradient(colors: [batteryTop, batteryBottom], startPoint: .top, endPoint: .bottom)
    }
}

struct OverviewView: View {
    @Bindable var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesPadLayout: Bool {
        AdaptiveLayout.usesPadConsole(horizontalSizeClass)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Overview")
                    .font(.system(size: usesPadLayout ? 34 : 28, weight: .regular))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, usesPadLayout ? 0 : 16)
            .padding(.bottom, 8)

            if !model.isLive {
                statusBanner
                    .padding(.horizontal, usesPadLayout ? 0 : 16)
                    .padding(.bottom, 8)
            }

            if usesPadLayout {
                padTileGrid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                phoneTileStack
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var phoneTileStack: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                gridTile
                solarTile
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)

            boltRow

            HStack(spacing: 12) {
                inverterTile
                batteryTile
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1.14)

            boltRow

            HStack(spacing: 12) {
                loadTile(title: "AC Loads", systemImage: "arrow.triangle.2.circlepath", amps: MetricFormat.acLoadValue(model.snapshot.acLoadAmps))
                loadTile(title: "DC Loads", systemImage: "circle.grid.cross", amps: model.snapshot.dcLoadAmps, plusWhenPositive: true)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var padTileGrid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 16
            let rowHeight = max(200, (geo.size.height - spacing) / 2)
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
            LazyVGrid(columns: columns, spacing: spacing) {
                padTileCell(gridTile, height: rowHeight)
                padTileCell(solarTile, height: rowHeight)
                padTileCell(inverterTile, height: rowHeight)
                padTileCell(batteryTile, height: rowHeight)
                padTileCell(
                    loadTile(title: "AC Loads", systemImage: "arrow.triangle.2.circlepath", amps: MetricFormat.acLoadValue(model.snapshot.acLoadAmps)),
                    height: rowHeight
                )
                padTileCell(
                    loadTile(title: "DC Loads", systemImage: "circle.grid.cross", amps: model.snapshot.dcLoadAmps, plusWhenPositive: true),
                    height: rowHeight
                )
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private func padTileCell<Content: View>(_ content: Content, height: CGFloat) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }

    private var statusBanner: some View {
        Button {
            model.tab = .settings
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.needsPassword ? "lock.fill" : "wifi.exclamationmark")
                Text(model.statusText)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(model.needsPassword ? "Password" : "Settings")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var gridTile: some View {
        Tile {
            VStack(alignment: .leading, spacing: 2) {
                LabelRow(title: "Grid") { GridGlyph() }
                Group {
                    if model.snapshot.gridAmps == nil {
                        Text(MetricFormat.gridTile(model.snapshot.gridAmps))
                            .font(.system(size: usesPadLayout ? 28 : 22, weight: .semibold))
                    } else {
                        Text(MetricFormat.gridTile(model.snapshot.gridAmps))
                            .font(TileFont.value(pad: usesPadLayout))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(Theme.signColor(model.snapshot.gridAmps))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            LevelMark(fraction: level(model.snapshot.gridAmps, fullScale: 30))
        }
    }

    private var solarTile: some View {
        Button {
            model.showSolar = true
        } label: {
            Tile {
                VStack(alignment: .leading, spacing: 2) {
                    LabelRow(title: "Solar") {
                        Image(systemName: "sun.max")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(MetricFormat.watts(solarPower))
                        .font(TileFont.value(pad: usesPadLayout))
                        .foregroundStyle(Theme.signColor(solarPower))
                        .monospacedDigit()
                    Text("\(MetricFormat.pvVolts(model.snapshot.solarPvVolts))   \(MetricFormat.pvCurrent(watts: solarPower, volts: model.snapshot.solarPvVolts))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 4) {
                        Text("Battery")
                        Text(MetricFormat.pvVolts(model.snapshot.solarBatteryVolts))
                        Text("|")
                        Text(solarBatteryAmps)
                            .foregroundStyle(Theme.signColor(model.snapshot.solarBatteryAmps))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    SolarChart(samples: model.solarHours.map(\.wattHours))
                        .frame(height: 32)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var solarPower: Double? {
        model.snapshot.solarPvWatts ?? model.snapshot.solarWatts
    }

    private var solarBatteryAmps: String {
        MetricFormat.ampsText(model.snapshot.solarBatteryAmps, plusWhenPositive: true)
    }

    private var inverterTile: some View {
        Button {
            model.devicePage = .inverter
        } label: {
            inverterCard
        }
        .buttonStyle(.plain)
    }

    private var inverterCard: some View {
        Tile {
            VStack(alignment: .leading, spacing: 6) {
                LabelRow(title: "Inverter / Charger") {
                    Image(systemName: "arrow.left.arrow.right.square")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(model.snapshot.inverterState)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            LevelMark(fraction: model.snapshot.inverterState == "—" ? 0.08 : 0.42)
        }
    }

    private var batteryTile: some View {
        Button {
            model.devicePage = .shunt
        } label: {
            batteryCard
        }
        .buttonStyle(.plain)
    }

    private var batteryCard: some View {
        Tile(chargeFraction: batteryFill) {
            VStack(alignment: .leading, spacing: 0) {
                LabelRow(title: "Battery") {
                    Image(systemName: "battery.100")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(MetricFormat.percent(model.snapshot.batterySOC))
                    .font(TileFont.value(pad: usesPadLayout))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.top, 2)
                Text(model.snapshot.batteryState.title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 1)
                Text(DetailText.timeToGo(model.snapshot.batteryTimeToGo))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MetricFormat.voltsText(model.snapshot.batteryVolts))
                        .foregroundStyle(.white)
                    Text(MetricFormat.ampsText(model.snapshot.batteryAmps, plusWhenPositive: true))
                        .foregroundStyle(Theme.signColor(model.snapshot.batteryAmps))
                    Text(MetricFormat.wattsText(model.snapshot.batteryWatts, plusWhenPositive: true))
                        .foregroundStyle(Theme.signColor(model.snapshot.batteryWatts))
                }
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            }
        }
    }

    private func loadTile(title: String, systemImage: String, amps: Double?, plusWhenPositive: Bool = false) -> some View {
        Tile {
            VStack(alignment: .leading, spacing: 2) {
                LabelRow(title: title) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(MetricFormat.amps(amps, plusWhenPositive: plusWhenPositive))
                    .font(TileFont.value(pad: usesPadLayout))
                    .foregroundStyle(Theme.signColor(amps))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
        }
    }

    private var boltRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
            Image(systemName: "bolt.fill")
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(Theme.bolt)
        .frame(height: 16)
    }

    private var batteryFill: Double {
        guard let soc = model.snapshot.batterySOC else { return 0 }
        return min(1, max(0, soc / 100))
    }

    private func level(_ value: Double?, fullScale: Double) -> Double {
        guard let value else { return 0.08 }
        return min(1, max(0.12, abs(value) / fullScale))
    }
}

private enum TileFont {
    static func value(pad: Bool) -> Font {
        .system(size: pad ? 44 : 36, weight: .regular)
    }
}

struct Tile<Content: View>: View {
    var chargeFraction: Double?
    @ViewBuilder var content: () -> Content

    init(chargeFraction: Double? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.chargeFraction = chargeFraction
        self.content = content
    }

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ChargeFill(fraction: chargeFraction ?? 0, showsCharge: chargeFraction != nil)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1.2)
            }
    }
}

struct ChargeFill: View {
    var fraction: Double
    var showsCharge: Bool

    var body: some View {
        GeometryReader { geo in
            let clamped = min(1, max(0, fraction))
            ZStack(alignment: .bottom) {
                Theme.card
                if showsCharge, clamped > 0 {
                    Theme.batteryGradient
                        .frame(height: geo.size.height * clamped)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct LabelRow<Icon: View>: View {
    var title: String
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        HStack(spacing: 6) {
            icon()
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Theme.label)
    }
}

struct LevelMark: View {
    var fraction: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Theme.bar.opacity(0.95))
            .frame(width: 5, height: 10 + 28 * fraction)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
    }
}

struct SolarHistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum FontScale {
        static let title = 25.5
        static let headline = 42.0
        static let body = 25.5
        static let detail = 22.5
        static let section = 22.5
        static let chartAxis = 18.0
        static let navIcon = 24.0
        static let closeIcon = 21.0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: FontScale.navIcon, weight: .semibold))
                        .frame(width: 63, height: 51)
                        .background(Color(red: 0.10, green: 0.18, blue: 0.30), in: Capsule())
                }
                .buttonStyle(.plain)
                Text(model.snapshot.solarName)
                    .font(.system(size: FontScale.title, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: FontScale.closeIcon, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 16) {
                Text(MetricFormat.mpptState(model.snapshot.solarState))
                    .font(.system(size: FontScale.headline, weight: .semibold))
                Text("Today  \(MetricFormat.yield(model.snapshot.solarYieldKWh))")
                    .font(.system(size: FontScale.body, weight: .medium))
                    .monospacedDigit()
                HStack(spacing: 12) {
                    Text(MetricFormat.pvVolts(model.snapshot.solarPvVolts))
                    Text(MetricFormat.pvCurrent(watts: solarHistoryPower, volts: model.snapshot.solarPvVolts))
                    Text(MetricFormat.wattsText(solarHistoryPower))
                        .foregroundStyle(Theme.signColor(solarHistoryPower))
                }
                .font(.system(size: FontScale.detail, weight: .medium))
                .monospacedDigit()
                HStack(spacing: 10) {
                    Text("Battery")
                    Text(MetricFormat.pvVolts(model.snapshot.solarBatteryVolts))
                    Text("|")
                    Text(batteryAmps)
                        .foregroundStyle(Theme.signColor(model.snapshot.solarBatteryAmps))
                }
                .font(.system(size: FontScale.detail, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)

            Text("Hourly yield")
                .font(.system(size: FontScale.section, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 8)

            HourlySolarChart(hours: model.solarHours, axisFontSize: FontScale.chartAxis)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)

            Spacer(minLength: 0)
        }
        .background(Color.black.ignoresSafeArea())
        .frame(maxWidth: AdaptiveLayout.padDetailMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var solarHistoryPower: Double? {
        model.snapshot.solarPvWatts ?? model.snapshot.solarWatts
    }

    private var batteryAmps: String {
        guard let amps = model.snapshot.solarBatteryAmps else { return "— A" }
        return String(format: "%.1f A", amps)
    }
}

struct HourlySolarChart: View {
    var hours: [SolarHourBar]
    var axisFontSize: CGFloat = 12

    var body: some View {
        let peak = max(hours.map(\.wattHours).max() ?? 0, 1)
        VStack(spacing: 8) {
            GeometryReader { geo in
                let count = max(hours.count, 1)
                let gap: CGFloat = count > 16 ? 3 : 5
                let width = max(4, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(hours) { bar in
                        let ratio = bar.wattHours / peak
                        let height = bar.wattHours < 1 ? 4 : max(10, geo.size.height * ratio)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(bar.wattHours < 1 ? Theme.barLow.opacity(0.45) : Theme.bar)
                            .frame(width: width, height: height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            HStack {
                if let first = hours.first?.hour, let last = hours.last?.hour {
                    Text(MetricFormat.hourLabel(first))
                    Spacer()
                    if last - first > 4 {
                        Text(MetricFormat.hourLabel((first + last) / 2))
                    }
                    Spacer()
                    Text(MetricFormat.hourLabel(last))
                }
            }
            .font(.system(size: axisFontSize, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .monospacedDigit()
        }
    }
}

struct SolarChart: View {
    var samples: [Double]

    var body: some View {
        let peak = max(samples.max() ?? 0, 1)
        GeometryReader { geo in
            let count = max(samples.count, 1)
            let gap: CGFloat = 3
            let width = max(2, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, watts in
                    let ratio = watts / peak
                    let height = watts < 8 ? 4 : max(8, geo.size.height * ratio)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(watts < 8 ? Theme.barLow.opacity(0.55) : Theme.bar)
                        .frame(width: width, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct GridGlyph: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let w = size.width
            let h = size.height
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.02))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.92))
            path.move(to: CGPoint(x: w * 0.08, y: h * 0.28))
            path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.28))
            path.move(to: CGPoint(x: w * 0.20, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.52))
            path.move(to: CGPoint(x: w * 0.22, y: h * 0.96))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.96))
            path.move(to: CGPoint(x: w * 0.22, y: h * 0.96))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.62))
            path.move(to: CGPoint(x: w * 0.78, y: h * 0.96))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.62))
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 16, height: 16)
    }
}
