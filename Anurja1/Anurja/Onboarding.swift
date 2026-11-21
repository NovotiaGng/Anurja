import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch state.stage {
            case .welcome:
                WelcomeView().transition(.opacity)
            case .connect:
                ConnectView().transition(.opacity)
            case .aboutYou:
                AboutYouView().transition(.opacity)
            case .allergies:
                AllergiesView().transition(.opacity)
            case .insulin:
                InsulinQuestionView().transition(.opacity)
            case .medicines:
                MedicinesView().transition(.opacity)
            case .allSet:
                AllSetView().transition(.opacity)
            case .main:
                Color.clear
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: state.stage)
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CreamBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 18) {
                        Text("Anurja")
                            .font(.system(size: 32, weight: .medium, design: .serif).italic())
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 8)
                        Spacer(minLength: 12)
                        ZStack {
                            Circle().fill(Color.paleDisc)
                            SunburstMark().padding(20)
                        }
                        .frame(width: min(290, geo.size.width - 48), height: min(290, geo.size.width - 48))
                        Spacer(minLength: 12)
                        Text("Your rhythm, quietly understood")
                            .scaledFont(size: 36, weight: .bold, design: .serif, relativeTo: .largeTitle)
                            .foregroundStyle(Color.maroon)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Anurja learns how your everyday meals shape your energy. No judgment, just your own natural pattern.")
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.forest)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryButton(title: "Begin your journey") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.advance()
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
    }
}

struct ConnectView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bothConnected: Bool {
        state.watchLink == .connected && state.cgmLink == .connected
    }

    var body: some View {
        ZStack {
            WarmBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        BackButton {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.goBack()
                            }
                        }
                        .padding(.leading, -10)
                        Text("YOUR FIRST TWO WEEKS")
                            .scaledFont(size: 13, weight: .semibold)
                            .tracking(1.1)
                            .foregroundStyle(Color.cream)
                            .padding(.top, 8)
                        Text("Let's learn your pattern,")
                            .scaledFont(size: 38, weight: .bold, design: .serif, relativeTo: .largeTitle)
                            .foregroundStyle(Color.cream)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("For two weeks, simply live your life. We'll quietly calibrate around your natural routine.")
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.cream)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        DeviceCard(
                            symbol: "applewatch",
                            title: state.watchLink == .connected ? String(localized: "Apple Watch Connected") : String(localized: "Apple Watch"),
                            subtitle: subtitle(for: state.watchLink),
                            state: state.watchLink
                        ) {
                            state.connectWatch()
                        }
                        DeviceCard(
                            symbol: "sensor.tag.radiowaves.forward",
                            title: state.cgmLink == .connected ? String(localized: "CGM Device Connected") : String(localized: "CGM Device"),
                            subtitle: subtitle(for: state.cgmLink),
                            state: state.cgmLink
                        ) {
                            state.connectCGM()
                        }
                        Spacer(minLength: 24)
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.skipConnect()
                            }
                        } label: {
                            Text("Skip for now, use demo data")
                                .scaledFont(size: 15)
                                .foregroundStyle(Color.cream.opacity(0.9))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        PrimaryButton(title: "Next", enabled: bothConnected) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.advance()
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
    }

    private func subtitle(for link: LinkState) -> String {
        switch link {
        case .idle: String(localized: "Tap to connect")
        case .connecting: String(localized: "Connecting…")
        case .connected: String(localized: "Calibrating in the background")
        }
    }
}

private struct DeviceCard: View {
    var symbol: String
    var title: String
    var subtitle: String
    var state: LinkState
    var connect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(Color.maroon)
                .frame(width: 60, height: 60)
                .background(Color.blush.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(size: 18, weight: .medium)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.forest)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(14)
        .background(Color.cream, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .idle:
            Button(action: connect) {
                Text("Connect")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.terracotta, in: Capsule())
            }
            .buttonStyle(.plain)
        case .connecting:
            ProgressView()
                .tint(Color.terracotta)
                .frame(width: 44, height: 44)
                .accessibilityLabel(Text("Connecting…"))
        case .connected:
            Circle()
                .fill(Color.terracotta)
                .frame(width: 22, height: 22)
                .accessibilityLabel(Text("Connected"))
        }
    }
}

// MARK: - Personalisation pages

/// Shared frame for the four "about you" steps: light sage page, segmented
/// step progress, white form card and a green Next button.
struct OnboardingPage<Content: View>: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var step: Int
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var enabled: Bool
    var skippable: Bool
    let content: Content

    init(step: Int, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, enabled: Bool = true, skippable: Bool = false, @ViewBuilder content: () -> Content) {
        self.step = step
        self.title = title
        self.subtitle = subtitle
        self.enabled = enabled
        self.skippable = skippable
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.mist.ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        Text(title)
                            .scaledFont(size: 34, weight: .heavy, relativeTo: .largeTitle)
                            .foregroundStyle(Color.deepInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                        if let subtitle {
                            Text(subtitle)
                                .scaledFont(size: 16)
                                .foregroundStyle(Color.deepInk.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        content
                        Spacer(minLength: 20)
                        Button {
                            move(state.advance)
                        } label: {
                            HStack(spacing: 10) {
                                Text("Next")
                                Image(systemName: "arrow.right").accessibilityHidden(true)
                            }
                            .scaledFont(size: 18, weight: .bold)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Color.terracotta, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled)
                        .opacity(enabled ? 1 : 0.45)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 8) {
                Text("Step \(step) of 4")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.deepInk.opacity(0.7))
                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Color.terracotta : Color.black.opacity(0.12))
                            .frame(width: 40, height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            HStack {
                Button {
                    move(state.goBack)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.deepInk)
                        .frame(width: 56, height: 56)
                        .background(Color.white, in: Circle())
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
                Spacer()
                if skippable {
                    Button("Skip") { move(state.advance) }
                        .scaledFont(size: 16, weight: .medium)
                        .foregroundStyle(Color.deepInk.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private func move(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { action() }
    }
}

struct AboutYouView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        OnboardingPage(
            step: 1,
            title: "Tell us about you",
            subtitle: "This helps Anurja read your numbers in context.",
            enabled: !state.profile.name.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            AboutYouFields(profile: $state.profile)
                .formCard()
            Label("This stays on your phone.", systemImage: "lock")
                .scaledFont(size: 14)
                .foregroundStyle(Color.deepInk.opacity(0.7))
                .padding(.leading, 12)
        }
    }
}

struct AllergiesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        OnboardingPage(step: 2, title: "Do you have any allergies?", skippable: true) {
            AllergyFields(profile: $state.profile)
                .padding(.top, 12)
        }
    }
}

struct InsulinQuestionView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        OnboardingPage(
            step: 3,
            title: "Do you take insulin?",
            subtitle: "If you do, Anurja adds a quick way to log the units you take next to your meals."
        ) {
            InsulinFields(profile: $state.profile)
        }
    }
}

struct MedicinesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        OnboardingPage(
            step: 4,
            title: "Your prescribed medicine",
            subtitle: "Add what your doctor prescribed. Anurja only keeps the list; it never changes or suggests doses."
        ) {
            MedicineFields(profile: $state.profile)
                .formCard()
        }
    }
}

struct AllSetView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CreamBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BackButton(tint: .terracotta) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { state.goBack() }
                        }
                        .padding(.leading, -10)
                        HStack {
                            Spacer()
                            ZStack {
                                Circle().fill(Color.paleDisc)
                                SunburstMark().padding(12)
                            }
                            .frame(width: 150, height: 150)
                            Spacer()
                        }
                        allSetTitle
                            .scaledFont(size: 34, weight: .bold, design: .serif, relativeTo: .largeTitle)
                            .foregroundStyle(Color.maroon)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Here is what Anurja will watch for. You can change any of it from Me.")
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.forest)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 10) {
                            summaryRow("target", "Fasting target", "70–130 mg/dL")
                            summaryRow("fork.knife", "After meals", "under 180 mg/dL")
                            summaryRow("figure.stand", "BMI", "\(state.profile.bmi.formatted(.number.precision(.fractionLength(1)))) · \(state.profile.bmiLabel)")
                            summaryRow("allergens", "Allergies", allergyText)
                            summaryRow("syringe", "Insulin", insulinText)
                            summaryRow("pills", "Medicines", medicineText)
                        }
                        .anurjaCard()
                        Spacer(minLength: 12)
                        PrimaryButton(title: "Go to my dashboard") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { state.advance() }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
    }

    private var allSetTitle: Text {
        if state.profile.firstName.isEmpty {
            return Text("You're all set")
        }
        return Text("You're all set, \(state.profile.firstName)")
    }

    private var allergyText: String {
        var names = state.profile.allergies.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        if !state.profile.otherAllergy.isEmpty { names.append(state.profile.otherAllergy) }
        return names.isEmpty ? String(localized: "None") : names.joined(separator: ", ")
    }

    private var insulinText: String {
        guard state.profile.takesInsulin else { return String(localized: "No") }
        return String(localized: "Yes")
    }

    private var medicineText: String {
        state.profile.medicines.isEmpty ? String(localized: "None added") : state.profile.medicines.map(\.name).joined(separator: ", ")
    }

    private func summaryRow(_ symbol: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.maroon)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .scaledFont(size: 15)
                .foregroundStyle(Color.muted)
            Spacer(minLength: 8)
            Text(value)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 32)
    }
}

// MARK: - Reusable profile fields (also used by Edit profile in Me)

struct AboutYouFields: View {
    @Binding var profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your name")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.deepInk.opacity(0.75))
                TextField("Name", text: $profile.name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .scaledFont(size: 17)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(Color.fieldGray, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.bottom, 16)
            Divider()
            MeasureRow(symbol: "calendar", tile: .tileGreen, tint: .leaf, title: "Age",
                       value: $profile.age, range: 12...100, label: { String(localized: "\($0) yrs") })
            Divider()
            MeasureRow(symbol: "ruler", tile: .tileBlue, tint: Color(hex: 0x3B6FB6), title: "Height",
                       value: Binding(get: { Int(profile.heightCm) }, set: { profile.heightCm = Double($0) }),
                       range: 120...220, label: { String(localized: "\($0) cm") })
            Divider()
            MeasureRow(symbol: "scalemass", tile: .tilePurple, tint: Color(hex: 0x6A55C2), title: "Weight",
                       value: Binding(get: { Int(profile.weightKg) }, set: { profile.weightKg = Double($0) }),
                       range: 30...200, label: { String(localized: "\($0) kg") })
            Divider()
            HStack(spacing: 14) {
                IconTile(symbol: "drop", tile: .tileOrange, tint: Color(hex: 0xC0592B))
                Text("BMI")
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Color.deepInk)
                Spacer(minLength: 8)
                Text(profile.bmi, format: .number.precision(.fractionLength(1)))
                    .scaledFont(size: 18, weight: .bold)
                    .foregroundStyle(Color.deepInk)
                Text(profile.bmiLabel)
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(healthy ? Color.leaf : Color(hex: 0xA5512A))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(healthy ? Color.tileGreen : Color.tileOrange, in: Capsule())
            }
            .padding(.vertical, 14)
        }
    }

    private var healthy: Bool { (18.5..<23).contains(profile.bmi) }
}

private struct IconTile: View {
    var symbol: String
    var tile: Color
    var tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Icon + label + value, as in the "Tell us about you" card.
/// Tapping the value opens a scroll wheel to pick it.
private struct MeasureRow: View {
    var symbol: String
    var tile: Color
    var tint: Color
    var title: LocalizedStringKey
    @Binding var value: Int
    var range: ClosedRange<Int>
    var label: (Int) -> String
    @State private var picking = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, tile: tile, tint: tint)
                Text(title)
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Color.deepInk)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { picking.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(label(value))
                            .scaledFont(size: 18, weight: .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.muted)
                    }
                    .foregroundStyle(Color.deepInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color.fieldGray, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(label(value)))
                .accessibilityHint(Text("Opens a scroll wheel"))
            }
            .padding(.vertical, 12)
            if picking {
                Picker(title, selection: $value) {
                    ForEach(Array(range), id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Grey checkbox row used by the allergies and medicines steps.
struct CheckRow: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24))
                    .foregroundStyle(selected ? Color.terracotta : Color.deepInk)
                    .accessibilityHidden(true)
                Text(title)
                    .scaledFont(size: 18)
                    .foregroundStyle(Color.deepInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 60)
            .background(Color.fieldGray, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Checkbox list plus "Add custom", as in the allergies step.
struct AllergyFields: View {
    @Binding var profile: UserProfile
    @State private var addingCustom = false
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CheckRow(title: String(localized: "None"), selected: profile.allergies.isEmpty && profile.otherAllergy.isEmpty) {
                profile.allergies = []
                profile.otherAllergy = ""
                addingCustom = false
            }
            // Common ones only, so Next stays on screen; anything else goes in Add Custom.
            ForEach(Allergy.allCases.filter { Allergy.common.contains($0) || profile.allergies.contains($0) }) { allergy in
                let selected = profile.allergies.contains(allergy)
                CheckRow(title: allergy.title, selected: selected) {
                    if selected { profile.allergies.remove(allergy) } else { profile.allergies.insert(allergy) }
                }
            }
            if addingCustom || !profile.otherAllergy.isEmpty {
                TextField("For example, mushrooms", text: $profile.otherAllergy)
                    .focused($customFocused)
                    .scaledFont(size: 18)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 60)
                    .background(Color.lime, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Button {
                    addingCustom = true
                    customFocused = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24))
                            .accessibilityHidden(true)
                        Text("Add Custom")
                            .scaledFont(size: 18)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.deepInk)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 60)
                    .background(Color.lime, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct InsulinFields: View {
    @Binding var profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionRow(symbol: "syringe", title: "Yes, I take insulin", subtitle: "Show insulin logging next to meals", selected: profile.takesInsulin) {
                profile.takesInsulin = true
                if profile.insulinType == nil { profile.insulinType = .rapid }
            }
            OptionRow(symbol: "xmark.circle", title: "No", subtitle: "You can turn it on later in Me", selected: !profile.takesInsulin) {
                profile.takesInsulin = false
                profile.insulinType = nil
            }
            if profile.takesInsulin {
                Text("Which kind?")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.deepInk)
                    .padding(.top, 6)
                ForEach(InsulinType.allCases) { type in
                    OptionRow(symbol: type.symbol, title: type.title, subtitle: type.subtitle, selected: profile.insulinType == type) {
                        profile.insulinType = type
                    }
                }
            }
            Text("Log only what you actually took. Anurja never suggests a dose.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.deepInk.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MedicineFields: View {
    @Binding var profile: UserProfile
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CheckRow(title: String(localized: "None"), selected: profile.medicines.isEmpty) {
                profile.medicines = []
            }
            Text("Common prescriptions")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            FlowLayout {
                ForEach(Medicine.common, id: \.self) { name in
                    Chip(title: name, selected: profile.medicines.contains { $0.name == name }) {
                        toggle(name)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Another medicine", text: $custom)
                    .textInputAutocapitalization(.words)
                    .scaledFont(size: 16)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Color.sand, lineWidth: 1))
                    .onSubmit(addCustom)
                Button(action: addCustom) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 48, height: 48)
                        .background(Color.terracotta, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("Add medicine"))
            }
            ForEach($profile.medicines) { $medicine in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(medicine.name)
                            .scaledFont(size: 16, weight: .bold)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Button {
                            profile.medicines.removeAll { $0.id == medicine.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.terracotta)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove \(medicine.name)"))
                    }
                    HStack(spacing: 8) {
                        TextField("Dose, e.g. 500 mg", text: $medicine.dose)
                            .scaledFont(size: 15)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color.cream, in: Capsule())
                        Picker("When", selection: $medicine.timing) {
                            ForEach(MedicineTiming.allCases) { timing in
                                Text(timing.localizedName).tag(timing)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.terracotta)
                    }
                }
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func toggle(_ name: String) {
        if profile.medicines.contains(where: { $0.name == name }) {
            profile.medicines.removeAll { $0.name == name }
        } else {
            profile.medicines.append(Medicine(name: name))
        }
    }

    private func addCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !profile.medicines.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            profile.medicines.append(Medicine(name: name))
        }
        custom = ""
    }
}

extension View {
    /// White panel used for form fields on the sage onboarding background.
    func formCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct BackButton: View {
    var tint: Color = .cream
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
    }
}

#Preview("Welcome") {
    WelcomeView().environmentObject(PreviewData.state())
}

#Preview("Connect") {
    ConnectView().environmentObject(PreviewData.state())
}

#Preview("About you") {
    AboutYouView().environmentObject(PreviewData.state())
}

#Preview("Medicines") {
    MedicinesView().environmentObject(PreviewData.state())
}

#Preview("All set") {
    AllSetView().environmentObject(PreviewData.state())
}
