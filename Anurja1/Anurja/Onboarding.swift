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

/// Shared frame for the four "about you" steps, in the same warm style as
/// Let's learn your pattern.
struct OnboardingPage<Content: View>: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var step: Int
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var enabled: Bool
    let content: Content

    init(step: Int, title: LocalizedStringKey, subtitle: LocalizedStringKey, enabled: Bool = true, @ViewBuilder content: () -> Content) {
        self.step = step
        self.title = title
        self.subtitle = subtitle
        self.enabled = enabled
        self.content = content()
    }

    var body: some View {
        ZStack {
            WarmBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        BackButton {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { state.goBack() }
                        }
                        .padding(.leading, -10)
                        Text("STEP \(step) OF 4")
                            .scaledFont(size: 13, weight: .semibold)
                            .tracking(1.1)
                            .foregroundStyle(Color.cream)
                            .padding(.top, 8)
                        Text(title)
                            .scaledFont(size: 36, weight: .bold, design: .serif, relativeTo: .largeTitle)
                            .foregroundStyle(Color.cream)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.cream)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        content
                        Spacer(minLength: 20)
                        PrimaryButton(title: "Next", enabled: enabled) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { state.advance() }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }
}

struct AboutYouView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        OnboardingPage(
            step: 1,
            title: "Tell us about you",
            subtitle: "This helps Anurja read your numbers in context. It stays on your phone.",
            enabled: !state.profile.name.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            AboutYouFields(profile: $state.profile)
                .formCard()
        }
    }
}

struct AllergiesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        OnboardingPage(
            step: 2,
            title: "Any allergies?",
            subtitle: "We'll keep these out of every food and snack we suggest."
        ) {
            AllergyFields(profile: $state.profile)
                .formCard()
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Your name")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            TextField("Name", text: $profile.name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .scaledFont(size: 17)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(Color.sand, lineWidth: 1))
            StepperRow(
                title: "Age",
                value: String(localized: "\(profile.age) yrs"),
                decreaseLabel: "Decrease age",
                increaseLabel: "Increase age",
                decrease: { profile.age = max(12, profile.age - 1) },
                increase: { profile.age = min(100, profile.age + 1) }
            )
            StepperRow(
                title: "Height",
                value: String(localized: "\(Int(profile.heightCm)) cm"),
                decreaseLabel: "Decrease height",
                increaseLabel: "Increase height",
                decrease: { profile.heightCm = max(120, profile.heightCm - 1) },
                increase: { profile.heightCm = min(220, profile.heightCm + 1) }
            )
            StepperRow(
                title: "Weight",
                value: String(localized: "\(Int(profile.weightKg)) kg"),
                decreaseLabel: "Decrease weight",
                increaseLabel: "Increase weight",
                decrease: { profile.weightKg = max(30, profile.weightKg - 1) },
                increase: { profile.weightKg = min(200, profile.weightKg + 1) }
            )
            HStack(alignment: .firstTextBaseline) {
                Text("BMI")
                    .scaledFont(size: 15)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(profile.bmi, format: .number.precision(.fractionLength(1)))
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(Color.ink)
                Text(profile.bmiLabel)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.forest)
            }
            .padding(.top, 2)
        }
    }
}

struct AllergyFields: View {
    @Binding var profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout {
                Chip(title: String(localized: "No allergies"), selected: profile.allergies.isEmpty && profile.otherAllergy.isEmpty) {
                    profile.allergies = []
                    profile.otherAllergy = ""
                }
                ForEach(Allergy.allCases) { allergy in
                    Chip(title: allergy.title, selected: profile.allergies.contains(allergy)) {
                        if profile.allergies.contains(allergy) {
                            profile.allergies.remove(allergy)
                        } else {
                            profile.allergies.insert(allergy)
                        }
                    }
                }
            }
            Text("Anything else?")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
                .padding(.top, 4)
            TextField("For example, mushrooms", text: $profile.otherAllergy)
                .scaledFont(size: 16)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(Color.sand, lineWidth: 1))
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
                    .foregroundStyle(Color.cream)
                    .padding(.top, 6)
                ForEach(InsulinType.allCases) { type in
                    OptionRow(symbol: type.symbol, title: type.title, subtitle: type.subtitle, selected: profile.insulinType == type) {
                        profile.insulinType = type
                    }
                }
            }
            Text("Log only what you actually took. Anurja never suggests a dose.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MedicineFields: View {
    @Binding var profile: UserProfile
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    /// Cream panel used for form fields on the warm onboarding background.
    func formCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cream, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
