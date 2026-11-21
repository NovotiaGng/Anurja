import Foundation
import CoreML
import UIKit
import Vision

/// One entry of the food library. The list itself lives in
/// FoodLibraryData.swift, generated from backend/data/foods.json so the app
/// and the server use the same nutrients. Keep the property order: the
/// generated file uses the memberwise initialiser.
struct FoodItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let category: String
    let serving: String
    let carbs: Double
    let fiber: Double
    let protein: Double
    let fat: Double
    let kcal: Double
    let gi: Double
    let group: String
    let allergens: [String]
    let keywords: [String]

    var mealFood: MealFood { MealFood(rawValue: group) ?? .somethingElse }

    func carbs(servings: Double) -> Int {
        Int((carbs * servings).rounded())
    }

    func isSafe(for profile: UserProfile) -> Bool {
        let other = profile.otherAllergy.lowercased().trimmingCharacters(in: .whitespaces)
        if !other.isEmpty, name.lowercased().contains(other) || keywords.contains(where: { $0.contains(other) }) {
            return false
        }
        return profile.allergenTags.isDisjoint(with: allergens)
    }
}

enum FoodLibrary {
    static var categories: [String] {
        var seen: [String] = []
        for item in all where !seen.contains(item.category) {
            seen.append(item.category)
        }
        return seen
    }

    static func item(id: String?) -> FoodItem? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static func defaultItem(for food: MealFood) -> FoodItem {
        let id: String
        switch food {
        case .riceDal: id = "rice_dal"
        case .idliDosa: id = "idli"
        case .roti: id = "roti_sabzi"
        case .biryani: id = "veg_biryani"
        case .salad: id = "salad_curd"
        case .somethingElse: id = "khichdi"
        }
        return item(id: id) ?? all[0]
    }

    static func search(_ text: String, category: String?) -> [FoodItem] {
        let query = text.lowercased().trimmingCharacters(in: .whitespaces)
        return all.filter { item in
            if let category, item.category != category { return false }
            guard !query.isEmpty else { return true }
            return item.name.lowercased().contains(query) || item.keywords.contains { $0.contains(query) }
        }
    }
}

/// On-device, offline photo recognition: Vision's image feature print, then
/// FoodClassifier.mlmodel (Core ML, trained by tools/foodvision on real photos
/// of Indian and world dishes, fruit and drinks). It suggests foods only when the model is confident;
/// the person always confirms on Review meal.
enum FoodRecognizer {

    /// Classifier label -> library foods, closest first. Dishes the library
    /// doesn't have (dhokla, jalebi, momos…) map to nothing, so a confident
    /// unknown dish opens the library instead of a wrong guess.
    static let libraryIDs: [String: [String]] = [
        "aloo_gobi": ["roti_sabzi"],
        "aloo_masala": ["roti_sabzi", "puri_aloo"],
        "apple": ["apple"],
        "bagel": ["bagel"],
        "banana": ["banana"],
        "bhindi_masala": ["roti_sabzi"],
        "biryani": ["veg_biryani", "chicken_biryani"],
        "burger": ["burger"],
        "burrito": ["burrito"],
        "butter_naan": ["naan_paneer"],
        "cake": ["cake"],
        "chai": ["masala_chai"],
        "chapati": ["roti_sabzi", "roti_dal", "multigrain_roti"],
        "chicken_curry": ["chicken_curry"],
        "chole": ["chana_masala"],
        "chole_bhature": ["chole_bhature"],
        "coconut_chutney": ["idli", "plain_dosa"],
        "coffee": ["black_coffee", "cappuccino"],
        "cookie": ["biscuits"],
        "croissant": ["croissant"],
        "dal_makhani": ["dal_tadka", "roti_dal", "rice_dal"],
        "doughnut": ["doughnut"],
        "fish_curry": ["fish_curry"],
        "french_fries": ["french_fries"],
        "grape": ["grapes"],
        "guacamole": ["guacamole"],
        "gulab_jamun": ["gulab_jamun"],
        "hot_dog": ["hot_dog"],
        "ice_cream": ["ice_cream"],
        "idli": ["idli"],
        "juice": ["fruit_juice"],
        "kadai_paneer": ["naan_paneer"],
        "kheer": ["kheer"],
        "lassi": ["mango_lassi", "buttermilk"],
        "mango": ["mango"],
        "masala_dosa": ["masala_dosa", "plain_dosa"],
        "muffin": ["muffin"],
        "noodles": ["noodles"],
        "orange": ["orange"],
        "pakode": ["pakora"],
        "palak_paneer": ["palak_paneer"],
        "pancake": ["pancakes"],
        "pizza": ["pizza"],
        "poha": ["poha"],
        "rajma_curry": ["rajma_chawal"],
        "salad": ["kachumber", "salad_curd", "sprouts_salad"],
        "samosa": ["samosa"],
        "sandwich": ["veg_sandwich"],
        "shahi_paneer": ["naan_paneer"],
        "soup": ["veg_soup"],
        "strawberry": ["strawberries"],
        "waffle": ["waffle"],
        "watermelon": ["watermelon"],
        "white_rice": ["rice_dal", "jeera_rice", "curd_rice"],
    ]

    private static let model: MLModel? = Bundle.main.url(forResource: "FoodClassifier", withExtension: "mlmodelc")
        .flatMap { try? MLModel(contentsOf: $0) }

    /// Lowest top-label confidence the app trusts, picked by train.py so 95 %
    /// of val photos at or above it were right. No model or no value: trust nothing.
    static let threshold: Double = (model?.modelDescription.metadata[.creatorDefinedKey] as? [String: String])?["threshold"]
        .flatMap(Double.init) ?? 1.01

    /// Empty when the top label is below `threshold` or not in the library.
    static func suggestions(for image: UIImage) async -> [FoodItem] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            rank(probabilities(cgImage, orientation: orientation))
        }.value
    }

    /// Vision's on-device feature print of the photo, then the dish model.
    private static func probabilities(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) -> [String: Double] {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2  // what the model was trained on
        guard let model,
              (try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])) != nil,
              let print = request.results?.first, print.elementType == .float,
              let features = try? MLMultiArray(shape: [NSNumber(value: print.elementCount)], dataType: .float32)
        else { return [:] }
        print.data.withUnsafeBytes { bytes in
            features.withUnsafeMutableBytes { out, _ in out.copyMemory(from: bytes) }
        }
        guard let output = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["featurePrint": features])) else { return [:] }
        return output.featureValue(for: "classLabelProbs")?.dictionaryValue as? [String: Double] ?? [:]
    }

    /// Confident labels' foods first, then the rest of the top 3 as alternatives.
    static func rank(_ probabilities: [String: Double]) -> [FoodItem] {
        let ranked = probabilities.sorted { $0.value > $1.value }.prefix(3)
        guard let top = ranked.first, top.value >= threshold, libraryIDs[top.key] != nil else { return [] }
        var ids: [String] = []
        for label in ranked.map(\.key) {
            for id in libraryIDs[label] ?? [] where !ids.contains(id) { ids.append(id) }
        }
        return ids.compactMap { FoodLibrary.item(id: $0) }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

enum MealPhotoStore {
    static func save(_ image: UIImage, id: UUID) -> String? {
        let name = "\(id.uuidString).jpg"
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func load(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(name).path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Anurja/MealPhotos", isDirectory: true)
    }
}
