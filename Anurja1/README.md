# Anurja

Anurja is a native SwiftUI app for people recently diagnosed with diabetes. It explains meal and activity patterns in a calm voice, suggests what to do when glucose leaves the target range, and never gives medication or insulin dosing advice.

Open `Anurja.xcodeproj` in Xcode 15 or later. The app targets iOS 17, portrait, iPhone only. The paired watch app targets watchOS 10. There are no third-party packages.

## App flow

```
Landing → Let's learn your pattern (Watch + CGM) → Tell us about you (name, age, height, weight → BMI)
→ Any allergies? → Do you take insulin? → Your prescribed medicine → You're all set → Dashboard (Home)
Tabs: Home · Trends · Meals · Habits · Me
  Meals  → Add meal → Camera / Food library → Review meal → insight → Log insulin pop-up
  Habits → Your next step (Next Goal, Remind me)
  Me     → Profile page
```

- **Home**: current glucose in mg/dL, Time in Target range, chart with an am/pm axis and a 12 hr / 24 hr / 1 week zoom, an abstract next-hour prediction (rise / fall / steady, no number), an immediate activity suggestion from the activity model (also sent as a pop-up notification when glucose is high or low), Est. GMI with a month-on-month comparison, Steps and Calories.
- **Trends**: opens instantly from the tab bar; glucose trend in mg/dL with the same zoom, Time in Target range, average, Est. GMI, Highest peak and Lowest peak (value, time, ↑/↓ change in mg/dL, and the meal before a peak).
- **Meals**: Add meal (camera, or food library with a search box and category drop-down), a Log insulin pop-up right below it (time, units, and whether it was before a meal, after a meal or around activity, matched automatically), Carbs today vs target, How your meals landed (↑ mg/dL rise), and What helps you (suggested snack, your meals compared with a lower-rise swap, foods that keep your glucose level steady, average rise by habit). Suggestions skip the person's allergies.
- **Habits**: Your change right now, Your next step, Walk after lunch (pre-filled from step counting), Was it difficult?, fortnightly review, and 8 camera-coached exercises.
- **Me**: profile, medical info, targets (fasting 70–130 mg/dL, after meals < 180 mg/dL, carbs per day), devices, notifications, server address and sync status.

## Machine learning

Two small neural networks are trained in `backend/ml/train.py` and run **on the phone** (weights exported into `Anurja/GeneratedModel.swift`, inference in `Anurja/MLEngine.swift`). The same models run on the server.

| Model | Input | Output | Holdout |
|---|---|---|---|
| Meal rise (MLP regressor, 17→24→1) | food nutrients × portion (carbs, glycaemic load, fibre, protein, fat), eating speed, desk / screen / on the move / walked / lay down, sweet drink, sugar, sleep, stress, time of day | expected glucose rise, mg/dL | MAE 5.7 mg/dL (noise floor 5.6) |
| Activity (MLP classifier, 7→16→4) | glucose, slope, time since last meal, fasting, steps in the last hour, time of day | in range / rising / high / low → suggested actions | 95.7 % accuracy |

Both start from synthetic data shaped by glycaemic-load physiology and the targets in the brief, then **personalise from the person's own logged meals**: each saved meal keeps the model's prediction and the sensor's real rise, and the residual (actual − predicted) is learned per food with shrinkage (`Personaliser` in `MLEngine.swift` and `backend/anurja_api/ml.py`). Activity suggestions are re-ranked by how much the person's own walks vs. strength sets lowered their glucose. A real low (< 70 mg/dL) always shows the low guidance, whatever the model says.

Photo recognition runs on the phone, offline: Vision's image feature print, then `Anurja/FoodModels/FoodClassifier.mlmodel` (Core ML, a softmax classifier over 71 dishes, fruit and drinks). Training data is real, freely licensed photos:

- 43 Indian dishes from [SohlHealth/enhanced-indian-food-classification](https://huggingface.co/datasets/SohlHealth/enhanced-indian-food-classification) (CC BY 4.0).
- 30 world dishes, fruit, coffee, tea and juice from [Open Images V7](https://storage.googleapis.com/openimages/web/index.html): human-verified image labels (CC BY 4.0) on Flickr photos (CC BY 2.0; per-photo credits in `tools/foodvision/openimages_credits.csv`).

`FoodRecognizer` (`Anurja/FoodLibrary.swift`) maps the model's labels onto the food library. When the top label is below the confidence threshold, or is a dish the library doesn't have, Add meal opens the food library instead of guessing. The person always confirms the food on Review meal. Per-dish top-1 / top-3 accuracy on held-out photos is in `tools/foodvision/report.json`. Korean, Japanese, Chinese and Thai dishes have no verified Open Images photos; `tools/foodvision/commons.py` collects them from Wikimedia Commons once you give it a contact for Wikimedia's User-Agent policy.

```bash
python3 -I tools/foodvision/prepare.py            # Indian dishes: download (~2 GB), dedupe, 70/15/15 split into tools/foodvision/data
python3 -I tools/foodvision/openimages.py fetch   # world dishes and drinks: verified labels + Flickr thumbnails, same split
swiftc -O -o /tmp/food-features tools/foodvision/ExtractFeatures.swift && /tmp/food-features
uv run -p 3.12 --with coremltools==9.0 --with scikit-learn==1.5.2 python -I tools/foodvision/train.py
```

Retrain and re-export after changing `backend/data/foods.json` or the features:

```bash
cd backend
python -m ml.train   # writes models/*.joblib, Anurja/GeneratedModel.swift, Anurja/FoodLibraryData.swift
```

## Database and backend

- **On the phone**: every meal, insulin dose, check-in and exercise session is saved in SQLite (`Anurja/LocalDatabase.swift`, `Application Support/Anurja/anurja.sqlite`) with a `synced` flag, so the app works offline. Settings stay in `state.json`.
- **Server** (`backend/`): FastAPI + SQLite. The app calls `POST /api/users/{id}/sync` after each change and `POST /api/ml/predict-rise` on Review meal, falling back to the on-device model when the server can't be reached.

```bash
cd backend
pip install -r requirements.txt
python -m ml.train                                        # only if models/ is missing
uvicorn anurja_api.main:app --host 0.0.0.0 --port 8000
python -m pytest -q                                       # API tests
```

API docs: http://localhost:8000/docs. The simulator reaches `http://localhost:8000` (the default). On an iPhone, set the server in **Me → Data & sync** to your Mac's Bonjour name, for example `http://my-mac.local:8000` (allowed by `NSAllowsLocalNetworking`). Use HTTPS for anything beyond local testing.

| Endpoint | Purpose |
|---|---|
| `GET /health` | status |
| `GET /api/foods?q=&category=` | food library |
| `PUT` / `GET /api/users/{id}` | profile |
| `POST /api/users/{id}/sync` | upsert meals, insulin, check-ins, sessions, glucose |
| `GET /api/users/{id}/{meals,insulin,checkins,sessions,glucose}` | list records |
| `POST /api/ml/predict-rise` | personalised meal rise |
| `POST /api/ml/recommend-activity` | status, target range, actions |
| `GET /api/users/{id}/insights/what-helps` | snack, swaps, steady foods, habit effects |

## Motion detection

- **Exercise coach**: Vision body pose on the front camera, one joint angle per exercise, smoothing, a full-range check, a tempo check ("Too quick"), a visibility check and a live "Movement detected" indicator. Exercises: bodyweight squat, chair sit-to-stand, split squat, knee-raise march, wall push-up, arm curl, overhead press, side arm raise.
- **Walk after a meal**: `CMPedometer` counts steps in the 90 minutes after the last meal and pre-fills "Did you do it?". Steps in the last hour also feed the activity model.

## Targets

| Scheme | Product | Bundle id |
|---|---|---|
| Anurja | iPhone app | `com.novotia.anurja` |
| AnurjaWatch | watchOS app, embedded in the iPhone app | `com.novotia.anurja.watchkitapp` |
| AnurjaWidget | Home and Lock Screen widget | `com.novotia.anurja.widget` |
| AnurjaWatchWidget | Watch complications | `com.novotia.anurja.watchkitapp.widget` |

Regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate`); `project.yml` is its source. The checked-in `Anurja.xcodeproj` already includes the new source files.

## Signing

Set a Development Team on Anurja, AnurjaWatch, AnurjaWidget, and AnurjaWatchWidget before running on a device. The App Group `group.com.novotia.anurja` must be enabled for the iPhone app, the widget, the watch app, and the watch widget. HealthKit must be enabled on the iPhone app.

## Info.plist

- `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`: meal photos and exercise form, processed on device.
- `NSHealthShareUsageDescription`: glucose, steps, active calories and sleep.
- `NSMotionUsageDescription`: step counting for the walk after a meal.
- `NSLocalNetworkUsageDescription`, `NSAppTransportSecurity › NSAllowsLocalNetworking`: syncing with a server on your network.
- Portrait only, light appearance, localizations `en`, `hi`, and `ta`.

## Real HealthKit

Glucose is simulated by default (seven days, so the week view has data). In `Anurja/AppState.swift`, set `useRealHealthKit` to `true`, sign the app with the HealthKit capability, and connect the CGM card. Anurja then reads blood glucose, step count, active energy and sleep, and loads the last 7 days of glucose in mg/dL. If that query is empty, the simulated trace stays in place.

## Camera coach on a device

The simulator runs the coached session as a simulated angle cycle and labels it “Camera unavailable here, running a simulated session”. On a real iPhone, Check my form uses the front camera and Vision body pose. Video is processed on device and is not stored or uploaded. To swap in MediaPipe Pose Landmarker, assign another `PoseFrameHandling` type to `PoseCameraController.frameHandler`.

## Decisions

- The gamified dashboard and the "What brings you here" choice were removed; everyone lands on Home after onboarding.
- Est. GMI (Glucose Management Indicator, 3.31 + 0.02392 × mean mg/dL) replaces HbA1c and is stored once a month for the comparison.
- BMI labels use the WHO Asian cut-offs (23 and 25).
- `Anurja1App.swift` and `ContentView.swift` are the old template and are not part of any target.

## Limitations

- Predictions are estimates, not medical advice, and Anurja never suggests a dose. The ML models start from synthetic training data and become personal as meals are logged.
- The "why this rise" explanations on the meal insight sheet are still the deterministic rule set (`InsightEngine.swift`).
- New strings are in English; Hindi and Tamil fall back to English until translated in `Localizable.xcstrings`.
- Watch “I ate” needs a paired, signed install so WatchConnectivity and the App Group can deliver the meal.
