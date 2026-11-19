import Foundation
import HealthKit

final class HealthKitService {
    private let store = HKHealthStore()

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount),
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        try? await store.requestAuthorization(toShare: [], read: [glucose, steps, sleep, energy])
    }

    func fetchGlucose(hours: Int) async -> [GlucosePoint] {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else { return [] }
        let start = Date().addingTimeInterval(-Double(hours) * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let points = (samples as? [HKQuantitySample])?.map {
                    GlucosePoint(time: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                } ?? []
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    func fetchStepsToday() async -> Int {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let count = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(count.rounded()))
            }
            store.execute(query)
        }
    }

    func fetchActiveCaloriesToday() async -> Int {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: Int(kcal.rounded()))
            }
            store.execute(query)
        }
    }

    func fetchSleepHours() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Date().addingTimeInterval(-36 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let asleep: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let seconds = ((samples as? [HKCategorySample]) ?? [])
                    .filter { asleep.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }
}
