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

class GoogleConfig {
  /// Resolved at startup by [load]. Empty means backup is not set up yet.
  static String clientId = kGoogleServerClientIdFromBuild;

  static bool get isSet => clientId.isNotEmpty;

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
