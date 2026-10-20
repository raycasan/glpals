# GLPals (personal tirzepatide tracker + Gemini buddy)

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
5. Run the app, open Settings, paste a Gemini API key from
   https://aistudio.google.com/apikey, pick the shot day. The key is kept in the
   device keychain. Link a billing account to the key's project to leave the free
   tier (no training on your data, no "high demand" rejections).

## Files
- lib/db.dart            SQLite models: shots, daily logs, streak, site rotation
- lib/reminders.dart     weekly shot-day notification
- lib/ai_service.dart    Gemini generateContent client; sends recent logs as context
- lib/screens/*          Home (pet), Shots, Check-in, Meals (photo + ingredients → AI estimate), Trends, Assistant

## Notes
- The assistant is prompted to explain and support only; it will not suggest
  dose changes and will point to the doctor for medical decisions.
- Cost: one request per question, ~1–2k tokens each on gemini-3.8-flash;
  gemini-3.7-flash is tried when it is busy.
- Meal estimates: typed ingredients with amounts override the photo; numbers are editable before saving.
- Ideas for v2: CSV export
  for doctor visits, Apple Health / Health Connect weight sync.
