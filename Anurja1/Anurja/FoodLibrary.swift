import Foundation
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

    /// Ranks library items against image labels from Vision.
    static func matches(labels: [(identifier: String, confidence: Float)]) -> [FoodItem] {
        var scores: [String: Float] = [:]
        for label in labels {
            let words = label.identifier.lowercased().replacingOccurrences(of: "_", with: " ")
            for item in all {
                let hit = item.keywords.contains { keyword in
                    words.contains(keyword) || keyword.contains(words)
                } || item.name.lowercased().contains(words)
                if hit {
                    scores[item.id, default: 0] += label.confidence
                }
            }
        }
        return scores
            .sorted { $0.value > $1.value }
            .prefix(6)
            .compactMap { item(id: $0.key) }
    }
}

/// On-device photo recognition with Apple's built-in image classifier. It
/// suggests likely foods; the person always confirms on Review meal.
enum FoodRecognizer {
    static func suggestions(for image: UIImage) async -> [FoodItem] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                let labels = (request.results ?? [])
                    .filter { $0.confidence > 0.05 }
                    .prefix(25)
                    .map { (identifier: $0.identifier, confidence: $0.confidence) }
                continuation.resume(returning: FoodLibrary.matches(labels: Array(labels)))
            }
        }
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
