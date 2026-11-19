import SwiftUI
import UIKit

/// Add meal → Camera / Food library → Review meal.
struct AddMealFlow: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Step { case choose, library, recognising, review }

    @State private var step: Step = .choose
    @State private var showCamera = false
    @State private var photo: UIImage?
    @State private var candidates: [FoodItem] = []
    @State private var chosen: FoodItem?

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                header
                switch step {
                case .choose:
                    chooser
                case .library:
                    FoodLibraryPicker { item in
                        chosen = item
                        candidates = []
                        step = .review
                    }
                case .recognising:
                    recognising
                case .review:
                    if let item = chosen {
                        ReviewMealView(item: item, candidates: candidates, photo: photo)
                            .id(item.id)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(source: UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary) { image in
                showCamera = false
                guard let image else { return }
                recognise(image)
            }
            .ignoresSafeArea()
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            if step != .choose {
                Button {
                    step = step == .review && candidates.isEmpty && photo == nil ? .library : .choose
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
            }
            Text(title)
                .scaledFont(size: 28, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(Color.ink)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case .choose: "Add meal"
        case .library: "Food library"
        case .recognising: "Looking at your plate"
        case .review: "Review meal"
        }
    }

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Snap your plate or pick it from the library. You can adjust everything before saving.")
                    .scaledFont(size: 15)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                OptionRow(symbol: "camera", title: "Camera", subtitle: "Take a photo and Anurja suggests the food", selected: false) {
                    showCamera = true
                }
                OptionRow(symbol: "books.vertical", title: "Food library", subtitle: "Search or browse by category", selected: false) {
                    step = .library
                }
                let recent = recentFoods
                if !recent.isEmpty {
                    Text("Recent")
                        .scaledFont(size: 17, weight: .bold)
                        .padding(.top, 8)
                    FlowLayout {
                        ForEach(recent) { item in
                            Chip(title: item.name, selected: false) {
                                chosen = item
                                candidates = []
                                photo = nil
                                step = .review
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var recognising: some View {
        VStack(spacing: 16) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            ProgressView()
                .tint(Color.terracotta)
            Text("Recognising on your phone…")
                .scaledFont(size: 15)
                .foregroundStyle(Color.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var recentFoods: [FoodItem] {
        var seen: [String] = []
        var items: [FoodItem] = []
        for meal in state.meals where !seen.contains(meal.foodItem.id) {
            seen.append(meal.foodItem.id)
            items.append(meal.foodItem)
            if items.count == 6 { break }
        }
        return items
    }

    private func recognise(_ image: UIImage) {
        photo = image
        step = .recognising
        Task {
            let found = await FoodRecognizer.suggestions(for: image)
            let safe = found.filter { $0.isSafe(for: state.profile) }
            candidates = safe.isEmpty ? found : safe
            if candidates.isEmpty {
                // Nothing recognised: fall back to the most common foods.
                candidates = ["rice_dal", "roti_sabzi", "idli", "salad_curd", "veg_biryani"].compactMap { FoodLibrary.item(id: $0) }
            }
            chosen = candidates.first
            step = .review
        }
    }
}

// MARK: - Food library

struct FoodLibraryPicker: View {
    var onPick: (FoodItem) -> Void
    @State private var query = ""
    @State private var category: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.muted)
                        .accessibilityHidden(true)
                    TextField("Search foods, e.g. dosa", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .scaledFont(size: 16)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(Color.sand, lineWidth: 1))
                Menu {
                    Button("All categories") { category = nil }
                    ForEach(FoodLibrary.categories, id: \.self) { name in
                        Button(name) { category = name }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(category ?? String(localized: "All"))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                    }
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color.terracotta, in: Capsule())
                }
                .accessibilityLabel(Text("Category"))
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    let results = FoodLibrary.search(query, category: category)
                    if results.isEmpty {
                        Text("No match. Try another word or pick a category.")
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.muted)
                            .padding(.top, 20)
                    }
                    ForEach(results) { item in
                        Button {
                            onPick(item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .scaledFont(size: 16, weight: .semibold)
                                        .foregroundStyle(Color.ink)
                                    Text("\(item.serving) · \(item.category)")
                                        .scaledFont(size: 12)
                                        .foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Text("\(Int(item.carbs)) g carbs")
                                    .scaledFont(size: 13, weight: .semibold)
                                    .foregroundStyle(Color.forest)
                            }
                            .anurjaCard(padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Review meal

struct ReviewMealView: View {
    @EnvironmentObject private var state: AppState
    let candidates: [FoodItem]
    let photo: UIImage?

    @State private var item: FoodItem
    @State private var servings = 1.0
    @State private var carbs: Int
    @State private var carbsEdited = false
    @State private var duration: MealDuration = .medium
    @State private var contexts: Set<MealContext> = [.desk]
    @State private var drink: Drink? = .water
    @State private var sugar = 0
    @State private var feelings: Set<Feeling> = []
    @State private var sleep = 6.5
    @State private var stress: Stress = .medium
    @State private var prediction: RisePrediction?
    @State private var saving = false

    init(item: FoodItem, candidates: [FoodItem], photo: UIImage?) {
        self.candidates = candidates
        self.photo = photo
        _item = State(initialValue: item)
        _carbs = State(initialValue: item.carbs(servings: 1))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                foodCard
                predictionCard
                FlowLayout {
                    ForEach(MealDuration.allCases) { value in
                        Chip(title: value.localizedName, selected: duration == value) { duration = value }
                    }
                    ForEach(MealContext.allCases) { context in
                        Chip(title: context.localizedName, selected: contexts.contains(context)) {
                            if contexts.contains(context) { contexts.remove(context) } else { contexts.insert(context) }
                        }
                    }
                }
                .anurjaCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("With the meal")
                        .scaledFont(size: 17, weight: .bold)
                    FlowLayout {
                        ForEach(Drink.allCases) { value in
                            Chip(title: value.localizedName, selected: drink == value) {
                                drink = drink == value ? nil : value
                            }
                        }
                    }
                    StepperRow(
                        title: "Sugar, spoons",
                        value: sugar.formatted(),
                        decreaseLabel: "Decrease sugar",
                        increaseLabel: "Increase sugar",
                        decrease: { sugar = max(0, sugar - 1) },
                        increase: { sugar = min(6, sugar + 1) }
                    )
                }
                .anurjaCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("How do you feel now?")
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(Color.forest)
                    Text("An hour or two after is best")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                    FlowLayout {
                        ForEach(Feeling.allCases) { feeling in
                            Chip(title: feeling.localizedName, selected: feelings.contains(feeling), forest: true) {
                                if feelings.contains(feeling) { feelings.remove(feeling) } else { feelings.insert(feeling) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Around this meal")
                        .scaledFont(size: 17, weight: .bold)
                    StepperRow(
                        title: "Sleep last night",
                        value: sleepLabel(sleep),
                        decreaseLabel: "Decrease sleep",
                        increaseLabel: "Increase sleep",
                        decrease: { sleep = max(2, sleep - 0.5) },
                        increase: { sleep = min(12, sleep + 0.5) }
                    )
                    Text("Stress today")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                    FlowLayout {
                        ForEach(Stress.allCases) { value in
                            Chip(title: value.localizedName, selected: stress == value) { stress = value }
                        }
                    }
                    FilledChip(title: String(localized: "From sensor: ↑ \(state.points.recentRise) mg/dL"))
                }
                .anurjaCard()

                PrimaryButton(title: "Save this meal", symbol: "chevron.right", enabled: !saving, action: save)
                    .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if let hours = state.healthSleepHours {
                sleep = (min(12, max(2, hours)) * 2).rounded() / 2
            }
        }
        .task(id: predictionKey) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            prediction = await state.predictRise(for: draft)
        }
    }

    private var foodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .scaledFont(size: 20, weight: .bold)
                        .foregroundStyle(Color.ink)
                    Text("\(item.serving) per serving · \(item.category)")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                }
            }
            if !candidates.isEmpty {
                HStack {
                    Text("Is this right?")
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.muted)
                    Spacer()
                    Menu {
                        ForEach(candidates) { option in
                            Button(option.name) { select(option) }
                        }
                        Divider()
                        ForEach(FoodLibrary.all) { option in
                            Button(option.name) { select(option) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Change food")
                            Image(systemName: "chevron.down")
                        }
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.terracotta)
                        .frame(minHeight: 44)
                    }
                }
            }
            StepperRow(
                title: "Portion",
                value: String(localized: "\(servings.formatted(.number.precision(.fractionLength(0...1)))) ×"),
                decreaseLabel: "Smaller portion",
                increaseLabel: "Bigger portion",
                decrease: { setServings(max(0.5, servings - 0.5)) },
                increase: { setServings(min(4, servings + 0.5)) }
            )
            StepperRow(
                title: "Carbs, grams",
                value: "\(carbs) g",
                decreaseLabel: "Decrease carbs",
                increaseLabel: "Increase carbs",
                decrease: { carbs = max(0, carbs - 5); carbsEdited = true },
                increase: { carbs = min(300, carbs + 5); carbsEdited = true }
            )
            Text("Carbs are estimated from the library. Adjust if you know better.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .anurjaCard()
    }

    private var predictionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(Color.maroon)
                .frame(width: 44, height: 44)
                .background(Color.blush.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("What to expect")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                if let prediction {
                    Text("\(prediction.band), about ↑ \(prediction.rise) mg/dL")
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(Color.ink)
                    Text(prediction.personalisedFrom > 0
                         ? String(localized: "Personalised from \(prediction.personalisedFrom) of your meals")
                         : String(localized: "Based on similar meals"))
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.forest)
                    if prediction.rise >= 55 {
                        Text("A 10-minute walk after eating can flatten this.")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.forest)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ProgressView().tint(Color.terracotta)
                }
            }
            Spacer(minLength: 0)
        }
        .anurjaCard()
    }

    private var predictionKey: String {
        "\(item.id)-\(servings)-\(carbs)-\(duration.rawValue)-\(contexts.map(\.rawValue).sorted())-\(drink?.rawValue ?? "")-\(sugar)-\(sleep)-\(stress.rawValue)"
    }

    private var draft: MealLog {
        MealLog(
            food: item.mealFood,
            duration: duration,
            contexts: contexts,
            drink: drink,
            sugarSpoons: sugar,
            feelings: feelings,
            sleepHours: sleep,
            stress: stress,
            rise: state.points.recentRise,
            carbsGrams: carbs,
            insulinUnits: nil,
            sourceID: nil,
            foodID: item.id,
            servings: servings,
            photoFile: nil,
            predictedRise: prediction?.rise
        )
    }

    private func select(_ option: FoodItem) {
        item = option
        carbsEdited = false
        carbs = option.carbs(servings: servings)
    }

    private func setServings(_ value: Double) {
        servings = value
        if !carbsEdited {
            carbs = item.carbs(servings: value)
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        var meal = draft
        if let photo {
            meal.photoFile = MealPhotoStore.save(photo, id: meal.id)
        }
        state.addMeal(meal)
    }
}

// MARK: - Insulin pop-up

struct InsulinSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var units = 4.0
    @State private var override: InsulinRelation?

    private var link: InsulinLink {
        InsulinLinker.link(dose: time, meals: state.meals, sessions: state.sessions, checkIns: state.checkIns)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Log insulin")
                            .scaledFont(size: 28, weight: .bold, relativeTo: .largeTitle)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.ink)
                                .frame(width: 44, height: 44)
                                .background(Color.white, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Close"))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        DatePicker("When did you take it?", selection: $time, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .scaledFont(size: 15)
                            .tint(Color.terracotta)
                        StepperRow(
                            title: "Units taken",
                            value: units.formatted(.number.precision(.fractionLength(0...1))),
                            decreaseLabel: "Decrease units",
                            increaseLabel: "Increase units",
                            decrease: { units = max(0.5, units - 0.5) },
                            increase: { units = min(100, units + 0.5) }
                        )
                    }
                    .anurjaCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Linked to")
                            .scaledFont(size: 17, weight: .bold)
                        Text(link.explanation)
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.forest)
                            .fixedSize(horizontal: false, vertical: true)
                        FlowLayout {
                            ForEach(InsulinRelation.allCases) { relation in
                                Chip(title: relation.title, selected: (override ?? link.relation) == relation) {
                                    override = relation == link.relation ? nil : relation
                                }
                            }
                        }
                        Text("Anurja matches the time with your meals and activity. Tap to change it.")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .anurjaCard()

                    Text("Log only what you actually took. Anurja never suggests a dose.")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Save insulin", symbol: "checkmark") {
                        let current = link
                        state.addInsulin(InsulinLog(
                            date: time,
                            units: units,
                            relation: override ?? current.relation,
                            mealID: current.meal?.id
                        ))
                        dismiss()
                    }
                }
                .padding(20)
            }
            .background(Color.cream)
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Camera

struct ImagePicker: UIViewControllerRepresentable {
    var source: UIImagePickerController.SourceType
    var onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
