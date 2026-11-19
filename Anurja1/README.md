# Anurja

Anurja is a native SwiftUI prototype for people recently diagnosed with diabetes. It explains meal and activity patterns in a calm voice. It does not give medication or insulin dosing advice.

Open `Anurja.xcodeproj` in Xcode 15 or later. The app targets iOS 17, portrait, iPhone only. The paired watch app targets watchOS 10. There are no third-party packages.

## Targets

| Scheme | Product | Bundle id |
|---|---|---|
| Anurja | iPhone app | `com.anurja.app` |
| AnurjaWatch | watchOS app, embedded in the iPhone app | `com.anurja.app.watchkitapp` |
| AnurjaWidget | Home and Lock Screen widget | `com.anurja.app.widget` |
| AnurjaWatchWidget | Watch complications | `com.anurja.app.watchkitapp.widget` |

WidgetKit complications need their own `@main` extension, so the watch face widgets live in `AnurjaWatchWidget` and are embedded in the watch app. The three schemes named in the product brief are Anurja, AnurjaWatch, and AnurjaWidget.

Regenerate the project the same way with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
```

`project.yml` is the source of that project file.

## Signing

Set a Development Team on Anurja, AnurjaWatch, AnurjaWidget, and AnurjaWatchWidget before running on a device. The App Group `group.com.anurja.app` must be enabled for the iPhone app, the widget, the watch app, and the watch widget. HealthKit must be enabled on the iPhone app. The entitlements file already requests HealthKit and the App Group.

Unsigned simulator builds (`CODE_SIGNING_ALLOWED=NO`) cannot create the App Group container. Widgets and the watch then show the “Open Anurja” placeholder until the app is signed.

## Info.plist

`Anurja/Info.plist` includes:

- `NSCameraUsageDescription`: Anurja uses the front camera to check your exercise form. Video stays on your device.
- `NSHealthShareUsageDescription`: Anurja reads glucose, steps and sleep to explain your meal patterns.
- Portrait only, light appearance, localizations `en`, `hi`, and `ta`.

## Real HealthKit

Glucose is simulated by default. In `Anurja/AppState.swift`, set `useRealHealthKit` to `true`, sign the app with the HealthKit capability, and connect the CGM card. Anurja then requests read access for blood glucose, step count, and sleep, and loads the last 24 hours of glucose in mg/dL. If that query is empty, the simulated trace stays in place.

## Camera coach on a device

The simulator always runs the coached session as a simulated angle cycle and labels it “Camera unavailable here, running a simulated session”. On a real iPhone, Check my form uses the front camera and Vision body pose. Video is processed on device and is not stored or uploaded. Allow camera access when asked.

To swap in MediaPipe Pose Landmarker later, replace `VisionPoseHandler` (or assign `PoseCameraController.frameHandler`) with another `PoseFrameHandling` type. That handler only needs to fill `joints` and `angle` on each frame. The rep counter, cues, and overlay stay the same.

## Language

English, Hindi, and Tamil ship in `Shared/Localizable.xcstrings`. The language follows the iPhone language setting. Me says so. Food names stay recognisable (dal, idli, dosa, roti, sabzi, biryani, curd).

## Decisions

- The medical disclaimer on Trends, the meal insight sheet, and Me is the longer safety sentence from the product brief.
- Insight suggestion copy follows the HTML preview: “Add vegetables or curd and eat them first, then the rice.” and “Here is what may have played a part.”
- Sample meals are shown in How I eat only until the first meal the user saves.
- Squat plan sizes are shown as sets: start is `max(1, minutes / 5)`, grow is `max(2, grow minutes / 5)`.
- The camera connection uses `videoRotationAngle` when 90° is supported. The deprecated `videoOrientation` fallback is omitted so the iOS 17 SDK build stays warning-free. iOS 17 supports the angle API.
- `Anurja1App.swift` and `ContentView.swift` are the old template and are not part of any target.

## Limitations

- Predictions are a short least-squares projection. They are estimates, not medical advice, and Anurja never suggests a dose.
- Carbs and insulin are stored exactly as entered. Nothing is calculated from them.
- A learned insight model is only an `InsightProviding` extension point. The shipped engine is the deterministic rule set.
- Watch “I ate” needs a paired, signed install so WatchConnectivity and the App Group can deliver the meal.
- Widget timelines refresh every 15 minutes and also when the app writes a new snapshot.
