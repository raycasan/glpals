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

## 3. Create two OAuth client IDs

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
