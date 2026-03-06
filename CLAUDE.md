# newsReels — Claude Code Instructions

## Project Structure

```
newsReels/
├── server.js            # Node.js/Express web server (Arab news aggregator)
├── package.json         # Web app dependencies (express, rss-parser)
└── flutter_app/         # Flutter mobile app (arab_news_reels)
    ├── lib/             # Dart source code
    │   ├── main.dart
    │   ├── models/      # Article, Video
    │   ├── screens/     # HomeScreen, ReelsScreen, LiveScreen, etc.
    │   ├── services/    # NewsService, VideoService, VideoStreamCache
    │   └── widgets/     # NewsReelCard, VideoReelCard, SourceFilter, etc.
    ├── test/            # Flutter unit & widget tests
    └── pubspec.yaml     # Flutter dependencies
```

## Flutter App (`flutter_app/`)

**Package name:** `arab_news_reels`
**SDK:** Dart ^3.7.0 / Flutter
**Platforms:** Android, iOS, macOS

### Install dependencies

```bash
cd flutter_app
flutter pub get
```

### Run

```bash
flutter run                        # debug on connected device/emulator
flutter run --release              # release mode
```

### Unit & Widget Tests

```bash
cd flutter_app

# Run all tests
flutter test

# Run a specific test file
flutter test test/widget_test.dart

# Run with verbose output
flutter test --reporter expanded

# Run with coverage
flutter test --coverage
# View coverage (requires lcov)
genhtml coverage/lcov.info -o coverage/html && open coverage/html/index.html
```

**Test file location:** `flutter_app/test/`
Add new test files as `flutter_app/test/<feature>_test.dart`.

### Static Analysis

```bash
cd flutter_app
flutter analyze
```

### Build

#### Android

```bash
cd flutter_app

# Debug APK
flutter build apk --debug

# Release APK (requires signing config)
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release
```

**Output:** `flutter_app/build/app/outputs/`

#### iOS (macOS only, requires Xcode)

```bash
cd flutter_app

# Release IPA
flutter build ipa --release
```

#### macOS

```bash
cd flutter_app
flutter build macos --release
```

**Output:** `flutter_app/build/macos/Build/Products/Release/`

### Key Dependencies

| Package | Purpose |
|---|---|
| `firebase_core` / `firebase_messaging` | Push notifications (FCM) |
| `flutter_local_notifications` | Foreground notification display |
| `video_player` | Native video playback |
| `youtube_explode_dart` | YouTube stream URL extraction |
| `webview_flutter` | In-app live stream embedding |
| `cached_network_image` | Image caching |
| `google_fonts` | Cairo font (Arabic support) |
| `share_plus` | Share articles |
| `url_launcher` | Open articles in browser |

### Firebase Note

`Firebase.initializeApp()` is called in `main()` before `runApp()`. Tests that import `main.dart` or widgets that depend on Firebase must mock or stub Firebase initialization — use `firebase_core_platform_interface` test helpers or `fake_firebase_core` in test dependencies.

---

## Web App (root `/`)

**Runtime:** Node.js
**Framework:** Express
**Entry point:** `server.js`

### Install dependencies

```bash
npm install
```

### Run

```bash
node server.js
# or
npm start
```

### Tests

The web app currently has no test framework configured. To add tests:

```bash
npm install --save-dev jest
# Add to package.json scripts:
#   "test": "jest"
npm test
```

---

## Deploy

### After every server-side change (`functions/index.js`)

Always deploy to Firebase Cloud Functions after modifying `functions/index.js`:

```bash
firebase deploy --only functions
```

This updates the live API at `https://us-central1-kol-dekeka.cloudfunctions.net/api` which the Flutter app uses. Run this from the project root (`/Users/ntgclarity/Documents/newsReels`).

> **Note:** `server.js` is the local dev server. `functions/index.js` is the production Cloud Function — keep both in sync when making feed/API changes.

---

## 🚀 "Go Live" Procedure

When the user says **"go live"**, execute all of the following steps in order:

1. **Commit all changes** to git with a descriptive message:
   ```bash
   git add -A
   git commit -m "your message here\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
   ```

2. **Push to GitHub**:
   ```bash
   git push origin main
   ```

3. **Deploy to Firebase Cloud Functions** (if `functions/index.js` was changed):
   ```bash
   firebase deploy --only functions
   ```

4. **Build and install Android APK** (if any Flutter files were changed):
   ```bash
   # Bump version in flutter_app/pubspec.yaml first (e.g. 1.0.0+2015 → 1.0.0+2016)
   cd flutter_app
   flutter build apk --release
   ~/Library/Android/sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

> Always bump `version` in `pubspec.yaml` before installing to avoid `INSTALL_FAILED_VERSION_DOWNGRADE`.

---

## Common Workflows

### Before committing Flutter changes

```bash
cd flutter_app
flutter analyze          # must pass with no errors
flutter test             # all tests must pass
```

### Adding a new Flutter test

1. Create `flutter_app/test/<name>_test.dart`
2. Import `package:flutter_test/flutter_test.dart`
3. For widget tests use `testWidgets()`; for unit tests use `test()`
4. Run with `flutter test test/<name>_test.dart`

### Upgrading Flutter dependencies

```bash
cd flutter_app
flutter pub upgrade --major-versions
flutter pub get
flutter analyze
flutter test
```
