import SwiftUI

/// Me tab: profile page.
struct ProfileView: View {
    @EnvironmentObject private var state: AppState
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: "Me", subtitle: nil, showsProfile: false)
                identityCard
                medicalCard
                targetsCard
                devicesCard
                alertsCard
                Text("Language follows your iPhone settings")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                    .padding(.horizontal, 4)
                DisclaimerText()
                    .padding(.horizontal, 4)
                Button("Restart demo") {
                    state.restart()
                }
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Color.terracotta)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $editing) {
            EditProfileSheet()
        }
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            Text(state.profile.initials)
                .scaledFont(size: 24, weight: .bold)
                .foregroundStyle(Color.white)
                .frame(width: 64, height: 64)
                .background(Color.terracotta, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.profile.name.isEmpty ? String(localized: "Add your name") : state.profile.name)
                    .scaledFont(size: 20, weight: .bold)
                    .foregroundStyle(Color.ink)
                Text("Age \(state.profile.age) · BMI \(state.profile.bmi.formatted(.number.precision(.fractionLength(1))))")
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.muted)
                Text(state.profile.bmiLabel)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.forest)
            }
            Spacer(minLength: 8)
            Button("Edit") { editing = true }
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.terracotta)
                .frame(minWidth: 44, minHeight: 44)
        }
        .anurjaCard()
    }

    private var medicalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Medical info")
                .scaledFont(size: 17, weight: .bold)
            row("allergens", "Allergies", allergyText)
            row("syringe", "Insulin", insulinText)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "pills")
                        .foregroundStyle(Color.maroon)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text("Prescribed medicine")
                        .scaledFont(size: 15)
                }
                if state.profile.medicines.isEmpty {
                    Text("None added")
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.muted)
                        .padding(.leading, 38)
                } else {
                    ForEach(state.profile.medicines) { medicine in
                        HStack {
                            Text(medicine.name)
                                .scaledFont(size: 14, weight: .semibold)
                            if !medicine.dose.isEmpty {
                                Text(medicine.dose)
                                    .scaledFont(size: 14)
                                    .foregroundStyle(Color.muted)
                            }
                            Spacer()
                            Text(medicine.timing.localizedName)
                                .scaledFont(size: 13)
                                .foregroundStyle(Color.forest)
                        }
                        .padding(.leading, 38)
                    }
                }
            }
        }
        .anurjaCard()
    }

    private var targetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your targets")
                .scaledFont(size: 17, weight: .bold)
            row("sunrise", "Fasting", "70–130 mg/dL")
            row("fork.knife", "After meals", "under 180 mg/dL")
            StepperRow(
                title: "Carbs per day",
                value: "\(state.profile.carbTarget) g",
                decreaseLabel: "Decrease carb target",
                increaseLabel: "Increase carb target",
                decrease: { state.profile.carbTarget = max(60, state.profile.carbTarget - 10) },
                increase: { state.profile.carbTarget = min(350, state.profile.carbTarget + 10) }
            )
            Text("Agree your targets with your care team.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.muted)
        }
        .anurjaCard()
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices")
                .scaledFont(size: 17, weight: .bold)
            deviceRow(symbol: "applewatch", name: "Apple Watch", connected: state.watchLink == .connected)
            deviceRow(symbol: "sensor.tag.radiowaves.forward", name: "CGM Device", connected: state.cgmLink == .connected)
            if state.stepsToday > 0 {
                Text("Steps today \(state.stepsToday)")
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.muted)
            }
        }
        .anurjaCard()
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .scaledFont(size: 17, weight: .bold)
            Toggle("Activity suggestions", isOn: $state.profile.activityAlerts)
                .tint(Color.terracotta)
            Text("A pop-up with what to do when your glucose goes above or below your target range.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .anurjaCard()
    }

    private var allergyText: String {
        var names = state.profile.allergies.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        if !state.profile.otherAllergy.isEmpty { names.append(state.profile.otherAllergy) }
        return names.isEmpty ? String(localized: "None") : names.joined(separator: ", ")
    }

    private var insulinText: String {
        guard state.profile.takesInsulin else { return String(localized: "No") }
        switch state.profile.insulinType {
        case .rapid: return String(localized: "Yes · rapid-acting")
        case .basal: return String(localized: "Yes · long-acting")
        case .both: return String(localized: "Yes · basal and meal-time")
        case .pump: return String(localized: "Yes · pump")
        case nil: return String(localized: "Yes")
        }
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.maroon)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title)
                .scaledFont(size: 15)
            Spacer(minLength: 8)
            Text(value)
                .scaledFont(size: 14)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 36)
    }

    private func deviceRow(symbol: String, name: LocalizedStringKey, connected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.maroon)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(name)
                .scaledFont(size: 15)
            Spacer()
            Text(connected ? "Connected" : "Not connected")
                .scaledFont(size: 14)
                .foregroundStyle(connected ? Color.forest : Color.muted)
        }
        .frame(minHeight: 44)
    }
}

struct EditProfileSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = UserProfile()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("About you") { AboutYouFields(profile: $draft) }
                    section("Allergies") { AllergyFields(profile: $draft) }
                    section("Insulin") {
                        Toggle("I take insulin", isOn: $draft.takesInsulin)
                            .tint(Color.terracotta)
                        if draft.takesInsulin {
                            Picker("Kind", selection: Binding(
                                get: { draft.insulinType ?? .rapid },
                                set: { draft.insulinType = $0 }
                            )) {
                                ForEach(InsulinType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.terracotta)
                        }
                    }
                    section("Prescribed medicine") { MedicineFields(profile: $draft) }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.cream)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if !draft.takesInsulin { draft.insulinType = nil }
                        state.profile = draft
                        state.sync()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { draft = state.profile }
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .scaledFont(size: 17, weight: .bold)
            content()
        }
        .anurjaCard()
    }
}

#Preview("Me") {
    ProfileView().environmentObject(PreviewData.state())
}
