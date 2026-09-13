# GLPals (personal tirzepatide tracker + Claude assistant)

## Setup
1. `flutter create glp_buddy` then copy `lib/`, `pubspec.yaml` over the generated ones.
2. `flutter pub get`
3. Android: in `android/app/src/main/AndroidManifest.xml` add
   `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`
   `<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>`
   `<uses-permission android:name="android.permission.CAMERA"/>`
   and set `minSdkVersion 23` in `android/app/build.gradle`.
   iOS: add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`.
4. iOS: `cd ios && pod install`. Notifications permission is requested on first launch.
5. Run the app, open Settings (gear icon), paste an Anthropic API key from
   https://platform.claude.com, pick the shot day. Key is kept in the device keychain.

## Files
- lib/db.dart            SQLite models: shots, daily logs, streak, site rotation
- lib/reminders.dart     weekly shot-day notification
- lib/claude_service.dart Messages API client; sends recent logs as context
- lib/screens/*          Home (pet), Shots, Check-in, Meals (photo + ingredients → AI estimate), Trends, Assistant

## Notes
- The assistant is prompted to explain and support only; it will not suggest
  dose changes and will point to the doctor for medical decisions.
- Cost: one request per question, ~1–2k tokens each on claude-sonnet-5.
- Meal estimates: typed ingredients with amounts override the photo; numbers are editable before saving.
- Ideas for v2: CSV export
  for doctor visits, Apple Health / Health Connect weight sync.
