import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var model: WatchModel
    @State private var eating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let snapshot = model.snapshot {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(snapshot.value, format: .number.precision(.fractionLength(0)))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Image(systemName: snapshot.trendSymbol)
                                .foregroundStyle(Color.terracotta)
                        }
                        Text("mg/dL")
                            .font(.caption2)
                            .foregroundStyle(Color.muted)
                        Text((Double(snapshot.timeInRange) / 100), format: .percent.precision(.fractionLength(0)))
                            .font(.headline)
                            .foregroundStyle(Color.forest)
                        Text("in range")
                            .font(.caption2)
                            .foregroundStyle(Color.muted)
                        SparklineChart(values: snapshot.recent)
                            .frame(height: 36)
                        Button("I ate") {
                            eating = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.terracotta)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Open Anurja on iPhone")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
            .navigationTitle("Anurja")
            .containerBackground(Color.cream, for: .navigation)
        }
        .sheet(isPresented: $eating) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(MealFood.allCases) { food in
                        Button(food.localizedName) {
                            model.sendMeal(food)
                            eating = false
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
    }
}
