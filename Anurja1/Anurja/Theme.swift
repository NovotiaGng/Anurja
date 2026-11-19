import SwiftUI

struct ScaledFontModifier: ViewModifier {
    var weight: Font.Weight
    var design: Font.Design
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        self.weight = weight
        self.design = design
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design, relativeTo: relativeTo))
    }

    func anurjaCard(padding: CGFloat = 15) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.sand, lineWidth: 1)
            )
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(for: subviews, maxWidth: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        var view: LayoutSubview
        var size: CGSize
    }

    private struct Row {
        var items: [Item]
        var height: CGFloat
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current: [Item] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let needed = current.isEmpty ? size.width : rowWidth + spacing + size.width
            if needed > maxWidth, !current.isEmpty {
                rows.append(Row(items: current, height: rowHeight))
                current = [Item(view: view, size: size)]
                rowWidth = size.width
                rowHeight = size.height
            } else {
                current.append(Item(view: view, size: size))
                rowWidth = needed
                rowHeight = max(rowHeight, size.height)
            }
        }
        if !current.isEmpty {
            rows.append(Row(items: current, height: rowHeight))
        }
        return rows
    }
}

struct PrimaryButton: View {
    var title: LocalizedStringKey
    var symbol: String = "arrow.right"
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .scaledFont(size: 17, weight: .semibold)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Color.terracotta, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct Chip: View {
    var title: String
    var selected: Bool
    var forest: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .scaledFont(size: 15, weight: selected ? .semibold : .regular)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? Color.white : Color.ink)
                .background(fill, in: Capsule())
                .overlay(Capsule().stroke(border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        guard selected else { return .clear }
        return forest ? .forest : .terracotta
    }

    private var border: Color {
        guard selected else { return .sand }
        return forest ? .forest : .terracotta
    }
}

struct FilledChip: View {
    var title: String

    var body: some View {
        Text(title)
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.terracotta, in: Capsule())
    }
}

struct OptionRow: View {
    var symbol: String
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.maroon)
                    .frame(width: 54, height: 54)
                    .background(Color.blush.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .stroke(Color.terracotta, lineWidth: 2)
                        .frame(width: 28, height: 28)
                    if selected {
                        Circle().fill(Color.terracotta).frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(selected ? Color.terracotta : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SegmentedTabs<Option: Hashable>: View {
    var options: [Option]
    var title: (Option) -> String
    @Binding var selection: Option
    @Namespace private var space

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .scaledFont(size: 15, weight: selection == option ? .semibold : .regular)
                        .foregroundStyle(selection == option ? Color.ink : Color.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 6)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(Color.white)
                                    .matchedGeometryEffect(id: "segment", in: space)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.sand, in: Capsule())
    }
}

struct CreamBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.cream
            Circle()
                .fill(Color.sand.opacity(0.85))
                .frame(width: 220, height: 220)
                .offset(x: 90, y: -100)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct WarmBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color.terracotta, Color.warmMid, Color.forest], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Color.sage.opacity(0.75))
                .frame(width: 300, height: 300)
                .offset(x: 110, y: -110)
            Circle()
                .fill(Color(hex: 0xE7B56A).opacity(0.28))
                .frame(width: 180, height: 180)
                .offset(x: -220, y: 280)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct SunburstMark: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            var path = Path()
            let count = 32
            for index in 0..<count {
                let angle = CGFloat(index) * 2 * .pi / CGFloat(count) - .pi / 2
                let spike: CGFloat
                if index % 2 == 1 {
                    spike = radius * 0.42
                } else if index % 4 == 0 {
                    spike = radius
                } else {
                    spike = radius * 0.78
                }
                let point = CGPoint(x: center.x + spike * cos(angle), y: center.y + spike * sin(angle))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            context.fill(path, with: .color(.forest))
            let creamRadius = radius * 0.42
            context.fill(Path(ellipseIn: CGRect(x: center.x - creamRadius, y: center.y - creamRadius, width: creamRadius * 2, height: creamRadius * 2)), with: .color(.cream))
            let ringRadius = radius * 0.30
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)),
                with: .color(.sand),
                lineWidth: max(3, radius * 0.035)
            )
            let core = radius * 0.27
            context.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)), with: .color(.maroon))
        }
        .accessibilityLabel(Text("Anurja"))
    }
}

struct ScreenHeader: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var showsProfile: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Text(title)
                    .scaledFont(size: 34, weight: .bold, relativeTo: .largeTitle)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if showsProfile {
                    ProfileButton()
                }
            }
            if let subtitle {
                Text(subtitle)
                    .scaledFont(size: 15)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ProfileButton: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button {
            state.showMe = true
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.cream, Color.terracotta)
                .font(.system(size: 34))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Profile"))
    }
}

struct DisclaimerText: View {
    var body: some View {
        Text("Anurja is not a medical device and does not give dosing advice. Always follow your care team's guidance.")
            .scaledFont(size: 12)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StepperRow: View {
    var title: LocalizedStringKey
    var value: String
    var decreaseLabel: LocalizedStringKey
    var increaseLabel: LocalizedStringKey
    var decrease: () -> Void
    var increase: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .scaledFont(size: 15)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: decrease) {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(decreaseLabel))
            Text(value)
                .scaledFont(size: 17, weight: .bold)
                .frame(minWidth: 72)
                .multilineTextAlignment(.center)
            Button(action: increase) {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(increaseLabel))
        }
    }
}

func sleepLabel(_ hours: Double) -> String {
    let totalMinutes = Int((hours * 60).rounded())
    let whole = totalMinutes / 60
    let minutes = totalMinutes % 60
    return String(localized: "\(whole) h \(minutes) m")
}

func trendWord(for symbol: String) -> String {
    switch symbol {
    case "arrow.up.right": String(localized: "Rising")
    case "arrow.down.right": String(localized: "Falling")
    default: String(localized: "Steady")
    }
}
