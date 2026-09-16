import 'dart:io';

import 'db.dart';

/// Google Sign-In configuration.
///
/// GLPals needs a *Web application* OAuth client ID from Google Cloud Console
/// (it is what Android's Credential Manager uses to identify the app). See
/// docs/google-backup-setup.md for the one-time setup steps.
///
/// The ID can come from three places, in order of precedence:
///  1. `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com`
///  2. [_pastedClientId] below, baked into the build
///  3. Pasted into Settings on the phone, stored in the settings table
///
/// The third exists so backup can be switched on without a rebuild, and so the
/// ID travels with a restored backup.
const kGoogleServerClientIdFromBuild = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: _pastedClientId,
);

const _pastedClientId =
    '931926600742-jlvjrhsav4g385ngd5bhg1pvick25eu9.apps.googleusercontent.com';

/// Settings key for an ID entered on the device.
const kGoogleClientIdSetting = 'google_server_client_id';

/// iOS identifies *itself* to Google with its own client ID, where Android
/// proves who it is with the signing certificate instead. So iOS needs a
/// second, iOS-type client ID, and unlike the Web one it cannot be pasted in
/// Settings: the matching `com.googleusercontent.apps.<id>` URL scheme has to
/// be in Info.plist at build time for Google to hand the sign-in back.
///
/// Leave this empty to let the plugin read `GIDClientID` from Info.plist,
/// which is the normal path. Setting it here (or with
/// `--dart-define=GOOGLE_IOS_CLIENT_ID=...`) overrides the plist, which is
/// handy in CI where the value is a secret.
const kGoogleIosClientIdFromBuild = String.fromEnvironment(
  'GOOGLE_IOS_CLIENT_ID',
  defaultValue: _pastedIosClientId,
);

const _pastedIosClientId = '';

class GoogleConfig {
  /// Resolved at startup by [load]. Empty means backup is not set up yet.
  static String clientId = kGoogleServerClientIdFromBuild;

  static bool get isSet => clientId.isNotEmpty;

  /// The ID the app identifies itself with, or null to let the platform work
  /// it out. Only ever non-null on iOS: handing an iOS client ID to Android
  /// makes Credential Manager reject every sign-in.
  static String? get appClientId {
    if (!Platform.isIOS || kGoogleIosClientIdFromBuild.isEmpty) return null;
    return kGoogleIosClientIdFromBuild;
  }

  static Future<void> load() async {
    if (kGoogleServerClientIdFromBuild.isNotEmpty) {
      clientId = kGoogleServerClientIdFromBuild;
      return;
    }
    clientId = await AppDb.instance.getSetting(kGoogleClientIdSetting) ?? '';
  }

  /// Saves an ID typed on the phone. Returns false if it does not look like a
  /// Google client ID, which catches the commonest paste mistake.
  static Future<bool> save(String raw) async {
    final id = raw.trim();
    if (!looksValid(id)) return false;
    clientId = id;
    await AppDb.instance.setSetting(kGoogleClientIdSetting, id);
    return true;
  }

  static bool looksValid(String id) =>
      id.endsWith('.apps.googleusercontent.com') && id.length > 30;
}
