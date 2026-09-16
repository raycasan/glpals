# Google backup setup (one time)

GLPals can back up all progress (shots, check-ins, meals, settings, and the
Gemini API key) to the signed-in Google account's private Drive app-data
folder. Google requires the app to be registered first. This takes about ten
minutes in Google Cloud Console.

## 1. Create a project and enable the Drive API

1. Open <https://console.cloud.google.com/> and create a project (for example
   "GLPals").
2. Go to **APIs & Services → Library**, search for **Google Drive API**, and
   click **Enable**.

## 2. Configure the OAuth consent screen

1. **APIs & Services → OAuth consent screen**.
2. User type **External**, fill in the app name (GLPals) and your email.
3. Under **Scopes**, add `https://www.googleapis.com/auth/drive.appdata`.
4. Under **Test users**, add the Google account(s) you will sign in with.
   (While the app is in "Testing" mode only listed users can sign in, which is
   fine for personal use.)

## 3. Create the OAuth client IDs

Android needs 3a and 3b. iPhone needs 3b and 3c. The Web client from 3b is
shared by both platforms: it is the one the Drive token is issued for.

**APIs & Services → Credentials → Create credentials → OAuth client ID**

### a) Android client

| Field | Value |
|---|---|
| Application type | Android |
| Package name | `com.glpbuddy.glp_buddy` |
| SHA-1 certificate fingerprint | `06:55:0E:AC:E2:0B:A4:80:6A:D6:04:69:84:B3:2B:BF:08:20:3B:90` |

That SHA-1 is the debug keystore on this development machine. The release
build currently signs with the same debug key, so one entry covers both. If you
later create a real release keystore, add its SHA-1 as a second Android client.

### b) Web application client

| Field | Value |
|---|---|
| Application type | Web application |
| Name | GLPals (Android sign-in) |

No redirect URIs are needed. Copy the generated **Client ID**
(`xxxx.apps.googleusercontent.com`).

### c) iOS client (only for the iPhone build)

| Field | Value |
|---|---|
| Application type | iOS |
| Bundle ID | `com.glpbuddy.glpBuddy` |

Note the bundle ID is *not* the same string as the Android package name: iOS
uses `com.glpbuddy.glpBuddy`, Android uses `com.glpbuddy.glp_buddy`. Copying
the Android one here is the easiest mistake to make, and it fails at sign-in
rather than at build time.

No App Store ID or Team ID is required while the app is not on the App Store.
Copy this second **Client ID**; it is different from the Web one and both are
needed on iOS.

## 4. Put the Web client ID into the app

Easiest: open **Settings** in the app, scroll to **Backup & sync**, paste the
Web client ID into the field and tap **Save client ID**. It is stored in the
settings table and sign-in starts working immediately, with no rebuild.

To bake it into the build instead, paste it into `lib/google_config.dart`:

```dart
const _pastedClientId = 'xxxx.apps.googleusercontent.com';
```

or build with a define:

```powershell
C:\flutter\bin\flutter.bat build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
```

Until an ID is set, the Settings sheet shows a "needs setup" note instead of
the sign-in button.

## 5. iOS: put the iOS client ID into Info.plist

**Already done in this repo** — `ios/Runner/Info.plist` carries the iOS client
ID for `com.glpbuddy.glpBuddy`. This section is here for when the ID changes,
or when the app is rebuilt under a different bundle id or Cloud project.

Unlike the Web client ID, this one cannot be set from the Settings screen: iOS
identifies the app by its own client ID, and Google hands the finished sign-in
back through a custom URL scheme that has to be registered in the app bundle at
build time.

The two entries take this shape:

```xml
<key>GIDClientID</key>
<string>1234-abcd.apps.googleusercontent.com</string>
...
<string>com.googleusercontent.apps.1234-abcd</string>
```

The two values are the same ID written two ways. The URL scheme is the client
ID with its halves swapped: drop `.apps.googleusercontent.com` from the end and
put `com.googleusercontent.apps.` on the front. It must not keep the
`.apps.googleusercontent.com` suffix.

To keep the ID out of version control, blank the `GIDClientID` value and build
with a define instead, which overrides the plist:

```bash
flutter build ipa --release --dart-define=GOOGLE_IOS_CLIENT_ID=1234-abcd.apps.googleusercontent.com
```

The URL scheme still has to be in Info.plist either way, so the define only
hides half the value. For a personal app the plist edit is simpler.

Symptoms when this step is skipped or wrong:

- Settings says "Google sign-in could not start" → `GIDClientID` is missing, or
  is not a real iOS-type client ID.
- The Google sheet opens, you pick the account, and the app never comes back
  or lands back signed out → the URL scheme is missing or malformed.
- Sign-in succeeds but Drive backup fails → the *Web* client ID from step 3b is
  wrong; that is the one the Drive token is minted for.

## Gemini on iOS

Nothing to configure. The assistant is a plain HTTPS call to Google's
Generative Language API with the key you paste into **Settings → Gemini API
key**, so it needs no OAuth client, no bundle registration and no entitlement.
It works on iPhone as soon as a key is saved, and a restored backup carries the
key over from Android.

The key lives per device, in the keychain. It does **not** travel inside the
app binary, so installing a fresh build on a new phone never brings it along.
Only three things can put it there: the setup flow, the Settings field, and a
Drive restore — which is why a phone that cannot sign in to Google also has no
assistant.

To skip the typing on a new phone, bake a key in at build time:

```bash
flutter build ipa --release --dart-define=GEMINI_API_KEY=AIza...
```

A key entered on the phone still wins over the baked one, so this is a starting
value rather than a lock. Two cautions: anything compiled into the app can be
read back out of the IPA by anyone holding it, so bake a key you are willing to
rotate; and pass it as a define rather than committing it, or add
`GEMINI_API_KEY` to the Codemagic "appstore" environment group and reference it
from the build script.

One iOS-only caveat: the key lives in the iOS keychain. If a TestFlight or
ad-hoc build ever loses the key between launches, or saving it fails with
OSStatus `-34018`, the build is missing keychain entitlements — add a
`Runner.entitlements` with `keychain-access-groups` and point
`CODE_SIGN_ENTITLEMENTS` at it. This has not been needed so far, so the file is
deliberately not in the project yet.

## What gets backed up

- All tables: shots, daily check-ins, meals, settings (theme, companion,
  reminder day).
- The Gemini API key, so the assistant works right after a restore on a new
  phone. It lives in your own Drive's hidden app-data area, which only GLPals
  can read. Remove the `gemini_api_key` line in `backup_service.dart` if you
  would rather keep the key device-only.
- Not included: meal photos (they stay on the phone).

Backups run automatically 8 seconds after a save when "Auto back up" is on, or
manually with **Back up now**. **Restore** replaces local data with the cloud
copy.

## Why there is no "sign in with Claude"

The Anthropic API is accessed with an API key from
<https://console.anthropic.com/>. Claude.ai consumer accounts (including ones
created with Google) cannot be used by third-party apps, and a Google account
carries no information about whether a Claude account exists. Backing up the
key with Google is the closest equivalent: sign in once on a new phone, restore,
and the buddy chat works immediately.
