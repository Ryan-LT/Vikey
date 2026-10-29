# Vikey for Android — plan and status

Tony, 2026-10-29: "lets build android version" (after Windows and Linux shipped). Parity target: the iOS keyboard
and app, feature for feature.

## How it works on Android

Vikey is an **input method service** (`app.vikey/.ime.VikeyIME`), the way every keyboard on Android works. The
system hands it the focused text field (an `InputConnection`), it draws the keyboard, and it commits text and
deletions back. Same `Engine/` C++ as macOS/Windows/Linux/iOS, built with the NDK into `libvikey.so`; the JNI
bridge `Android/app/src/main/cpp/vikey_jni.cpp` mirrors `iOS/Shared/VKDriver.mm`.

| iOS feature | Android |
|---|---|
| Telex, tone placement, spelling, restore-if-invalid, auto switch, Backspace undo, 5 s pause | same `Engine/Driver` through JNI (`ime/VikeyDriver.kt`) |
| Keyboard layout (iOS 26 geometry: 402 pt base, 43 pt keys, 54 pt pitch, 6 pt gaps, 44 pt strip) | `ime/KeyboardView.kt`, one Canvas-drawn view, same numbers in dp, scaled by width |
| Fat-finger model, auto-correct, suggestions strip, contractions | `TouchModel` through JNI; `VikeyIME.updateSuggestions` is a line-by-line port of the iOS controller |
| Key popup, long-press alternates (ă â á … – ’ ₫), slide from 123 to a symbol, cursor mode on the space bar, delete repeat → words | `KeyboardView` touches (Handler timers instead of `Timer`) |
| Emoji keyboard: categories, recents, skin tones, search in VI/EN/Telex, search mode above the letters | `ime/EmojiKeyboardView.kt` (custom view, fling scroll), `ime/EmojiIndex.kt`; only emoji the device font can draw (`Paint.hasGlyph`) |
| Auto-capitalize, double-space period, English for web/email fields, return key titles (Đi/Tìm/Gửi/Xong/Tiếp) | `EditorInfo` input type + IME action |
| Haptics / key click | `VibrationEffect.EFFECT_TICK` (no Full Access needed on Android) / `AudioManager` key click |
| Settings app, onboarding, demo card, acknowledgements, typing diagnostics + log | Jetpack Compose (`ui/`), same sections and tips as `iOS/App/MainView.swift`; log at `filesDir/keyboard-log.txt`, shared with the share sheet |
| Globe key | shown when another keyboard is enabled; tap = next keyboard, hold = picker |
| Dark mode | follows the system (keyboard + app) |

Not on Android: Full Access (not a concept), app-group defaults (one process: `SharedPreferences` read on every
keyboard open).

## Build, test, release

- Toolchain: `~/.tools/android_env.sh` (openjdk 21, SDK 35, NDK 27.2, CMake 3.22). `cd Android && ./gradlew assembleDebug`.
- Emulator: AVD `Vikey-Dev` (Pixel 7, API 35 arm64, headless: `emulator -avd Vikey-Dev -no-window -no-audio`).
  Enable + select: `adb shell ime enable app.vikey/.ime.VikeyIME && adb shell ime set app.vikey/.ime.VikeyIME`.
- Live test: `python3 Android/Tests/livetest.py` taps the keyboard through the real touch path and reads the
  field back, same cases as `Windows/Tests/cases.tsv` (14/14 on 2026-10-29). Needs a debug build (the
  `app.vikey.DEBUG` broadcast sets the language quietly, like `setLanguageForTests` on iOS).
- Release: tag `v<ver>` → `.github/workflows/android.yml` builds `Vikey-<ver>.apk` signed with the release
  keystore (secrets `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PROPERTIES`; keystore + passwords in
  `~/.secrets/vikey_android_keystore.*`, certificate SHA-256 `C2:87:4A:2B:…:5E:35`) and puts it on the GitHub
  release; `Tools/release/release.sh --android <ver>` verifies the signature, copies it to vikey.app/downloads,
  writes `release.json.android` and deploys the site (the download page shows the Android card from that key).
- Version = `project.yml` MARKETING_VERSION (versionCode 1.0.16 → 10016).
- Google Play: the company account is being created (2026-10-29); the same build goes through the Play Console
  as an AAB (`./gradlew bundleRelease`) once it exists.

## Status

- 2026-10-29: keyboard, emoji keyboard, app (onboarding, settings, acknowledgements) done; live test 14/14 on the
  emulator; release build signed and tested. Not yet tried on a physical phone.
