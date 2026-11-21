import SwiftUI

/// Train tab: guided strength and movement exercises.
struct HabitsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(
                    title: "Strength & movement",
                    subtitle: "Guided by your front camera. We check your form and count clean reps. Video never leaves your phone."
                )
                ForEach(ExerciseKind.allCases) { exercise in
                    Button {
                        state.coach = exercise
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: exercise.symbol)
                                .font(.system(size: 22))
                                .foregroundStyle(Color.maroon)
                                .frame(width: 54, height: 54)
                                .background(Color.blush.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.title)
                                    .scaledFont(size: 16, weight: .bold)
                                    .foregroundStyle(Color.ink)
                                Text(exercise.blurb)
                                    .scaledFont(size: 13)
                                    .foregroundStyle(Color.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.terracotta)
                                .accessibilityHidden(true)
                        }
                        .anurjaCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(exercise.title))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

#Preview("Train") {
    MainTabView().environmentObject(PreviewData.state(tab: .habits))
}
