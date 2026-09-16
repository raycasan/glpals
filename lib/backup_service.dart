import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'ai_service.dart';
import 'db.dart';
import 'google_config.dart';
import 'med.dart';
import 'theme.dart';
import 'widgets/pet.dart';

/// Which long-running job is in flight, so the spinner lands on the button
/// that was actually pressed.
enum BackupTask { none, signIn, signOut, backup, restore }

/// Where the Google connection stands, in terms the UI can speak plainly.
enum GoogleLink {
  /// No client ID yet, so there is nothing to connect to.
  unconfigured,

  /// Never connected on this device, or deliberately signed out.
  signedOut,

  /// An account is remembered and the silent restore is in flight.
  restoring,

  /// Connected and ready to back up.
  connected,

  /// An account is remembered but Google would not restore it silently.
  /// One tap fixes it; this is not the same as being signed out.
  needsReconnect,
}

/// Backs up all progress to the signed-in Google account's private Drive
/// app-data folder (invisible in the Drive UI, scoped to this app only).
///
/// The connection is meant to survive app restarts: the account is remembered
/// locally so the UI can say who is signed in straight away, while the silent
/// restore happens in the background. Signing in by hand should be a one-time
/// thing, not a daily ritual.
class BackupService extends ChangeNotifier {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  static const _fileName = 'glpals_backup.json';
  static const _filesUrl = 'https://www.googleapis.com/drive/v3/files';
  static const _uploadUrl = 'https://www.googleapis.com/upload/drive/v3/files';

  GoogleSignInAccount? account;
  bool busy = false;

  /// What [busy] is busy with.
  BackupTask task = BackupTask.none;

  bool isRunning(BackupTask t) => busy && task == t;
  String? lastError;

  /// Identity remembered from the last successful sign-in, so a cold start can
  /// show the account before Google has answered.
  String? rememberedEmail;
  String? rememberedName;
  String? rememberedPhoto;

  GoogleLink link = GoogleLink.unconfigured;

  /// Retries the silent restore when the app comes back to the foreground;
  /// Credential Manager often refuses right at cold start and succeeds later.
  AppLifecycleListener? _lifecycle;

  /// What just worked, shown in Settings. A snackbar alone is not enough:
  /// it appears behind the settings sheet.
  String? lastMessage;
  DateTime? lastBackup;
  bool autoBackup = true;
  bool _initialized = false;
  Timer? _debounce;

  /// True once a Web client ID is known (build define, pasted constant, or
  /// entered in Settings).
  bool get configured => GoogleConfig.isSet;
  bool get signedIn => account != null;

  /// True when an account is known, even if the session is still being
  /// restored. The UI uses this to avoid flashing a sign-in button at someone
  /// who signed in weeks ago.
  bool get hasAccount => account != null || rememberedEmail != null;

  String get accountLabel =>
      account?.displayName ??
      account?.email ??
      rememberedName ??
      rememberedEmail ??
      'your Google account';

  String? get accountEmail => account?.email ?? rememberedEmail;
  String? get accountPhoto => account?.photoUrl ?? rememberedPhoto;

  /// One line describing the connection, in our words rather than Google's.
  String get linkMessage => switch (link) {
        GoogleLink.unconfigured => 'Backup is not set up yet.',
        GoogleLink.signedOut =>
          'Sign in once to keep your shots, check-ins and meals safe in your '
              'own Google Drive. You stay signed in afterwards.',
        GoogleLink.restoring => 'Reconnecting to $accountLabel…',
        GoogleLink.connected => 'Connected. Backups run on their own.',
        GoogleLink.needsReconnect =>
          'Google needs you to confirm it is you again. This happens '
              'occasionally, and one tap restores the connection.',
      };

  /// True once the plugin has been handed the client ID for this process.
  bool _sdkReady = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final db = AppDb.instance;
    final last = await db.getSetting('last_backup_at');
    lastBackup = last == null ? null : DateTime.tryParse(last);
    autoBackup = (await db.getSetting('auto_backup') ?? 'true') == 'true';
    String? nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;
    rememberedEmail = nonEmpty(await db.getSetting('google_email'));
    rememberedName = nonEmpty(await db.getSetting('google_name'));
    rememberedPhoto = nonEmpty(await db.getSetting('google_photo'));
    await GoogleConfig.load();
    link = !configured
        ? GoogleLink.unconfigured
        : rememberedEmail == null
            ? GoogleLink.signedOut
            : GoogleLink.restoring;
    _lifecycle ??= AppLifecycleListener(onResume: () {
      // Cheap: returns immediately unless a remembered account is still
      // waiting to be restored.
      unawaited(retryRestore());
    });
    // Deliberately not awaited: Google's initialize and silent-sign-in can sit
    // for a long time on a slow or unusual network, and the splash must never
    // wait on them. Listeners are notified when it finishes.
    unawaited(_startSdk());
    notifyListeners();
  }

  /// Hands the client ID to the plugin and picks up any existing session.
  /// Safe to call again after an ID is entered on the device.
  Future<void> _startSdk() async {
    if (_sdkReady || !configured) return;
    try {
      final signIn = GoogleSignIn.instance;
      // clientId is who the app says it is (iOS only; null elsewhere, and on
      // iOS null means "read GIDClientID from Info.plist"). serverClientId is
      // the Web client the Drive tokens are minted for, on every platform.
      await signIn
          .initialize(
            clientId: GoogleConfig.appClientId,
            serverClientId: GoogleConfig.clientId,
          )
          .timeout(const Duration(seconds: 20));
      signIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          account = event.user;
          unawaited(_remember(event.user));
          link = GoogleLink.connected;
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          account = null;
          link = rememberedEmail == null
              ? GoogleLink.signedOut
              : GoogleLink.needsReconnect;
        }
        notifyListeners();
      });
      _sdkReady = true;
      notifyListeners();
    } catch (e) {
      lastError = 'Google sign-in could not start: $e';
      notifyListeners();
      return;
    }
    await _restoreSession();
  }

  /// Asks Google to hand the session back without showing anything. Failing
  /// is normal at cold start, so it downgrades to "needs reconnect" rather
  /// than pretending the user never signed in.
  Future<void> _restoreSession() async {
    if (!_sdkReady) return;
    try {
      final restored = await GoogleSignIn.instance
          .attemptLightweightAuthentication()
          ?.timeout(const Duration(seconds: 20));
      if (restored != null) {
        account = restored;
        await _remember(restored);
        link = GoogleLink.connected;
        lastError = null;
      } else {
        link = rememberedEmail == null
            ? GoogleLink.signedOut
            : GoogleLink.needsReconnect;
      }
    } catch (_) {
      // A refusal here is not worth an error message: the banner already
      // explains that one tap reconnects.
      link = rememberedEmail == null
          ? GoogleLink.signedOut
          : GoogleLink.needsReconnect;
    }
    notifyListeners();
  }

  /// Tries the silent restore again, used when the app returns to the
  /// foreground. Does nothing once connected.
  Future<void> retryRestore() async {
    if (!configured || signedIn || rememberedEmail == null) return;
    link = GoogleLink.restoring;
    notifyListeners();
    await _startSdk();
    if (_sdkReady && !signedIn) await _restoreSession();
  }

  Future<void> _remember(GoogleSignInAccount a) async {
    rememberedEmail = a.email;
    rememberedName = a.displayName;
    rememberedPhoto = a.photoUrl;
    final db = AppDb.instance;
    await db.setSetting('google_email', a.email);
    if (a.displayName != null) {
      await db.setSetting('google_name', a.displayName!);
    }
    if (a.photoUrl != null) await db.setSetting('google_photo', a.photoUrl!);
  }

  Future<void> _forget() async {
    rememberedEmail = null;
    rememberedName = null;
    rememberedPhoto = null;
    final db = AppDb.instance;
    for (final k in ['google_email', 'google_name', 'google_photo']) {
      await db.setSetting(k, '');
    }
  }

  /// Stores a client ID typed on the phone and brings sign-in to life without
  /// a rebuild. Returns false if the ID is not shaped like a Google client ID.
  Future<bool> saveClientId(String raw) async {
    final ok = await GoogleConfig.save(raw);
    if (!ok) {
      lastError = 'That does not look like a client ID. It should end in '
          '.apps.googleusercontent.com';
      notifyListeners();
      return false;
    }
    lastError = null;
    await _startSdk();
    notifyListeners();
    return true;
  }

  Future<void> signIn() async {
    await _run(task: BackupTask.signIn, () async {
      await _startSdk();
      if (!_sdkReady) {
        throw StateError(
            'Google sign-in could not start. Check the client ID in Settings.');
      }
      final signed =
          await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
      account = signed;
      await _remember(signed);
      link = GoogleLink.connected;
      // Ask for Drive access straight away so the first backup, and every one
      // after a restart, needs no further tapping.
      try {
        await signed.authorizationClient
            .authorizationHeaders(_scopes, promptIfNecessary: true);
      } catch (_) {
        // The backup itself will ask again if this was declined.
      }
    });
  }

  Future<void> signOut() async {
    await _run(task: BackupTask.signOut, () async {
      await GoogleSignIn.instance.signOut();
      account = null;
      await _forget();
      link = GoogleLink.signedOut;
      lastMessage = 'Signed out. Your data stays on this phone, and the cloud '
          'copy stays in your Drive.';
    });
  }

  Future<void> setAutoBackup(bool on) async {
    autoBackup = on;
    await AppDb.instance.setSetting('auto_backup', on ? 'true' : 'false');
    notifyListeners();
  }

  /// Debounced backup after a save. Runs when an account is remembered even
  /// if the session is still asleep: the upload path wakes it first.
  void scheduleAutoBackup() {
    if (!autoBackup || !hasAccount) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 8), () {
      backupNow().catchError((_) {});
    });
  }

  /// Uploads a full snapshot: all tables plus the Gemini API key so the
  /// assistant works right away after a restore on a new phone.
  Future<void> backupNow() async {
    await _run(task: BackupTask.backup, () async {
      final headers = await _headers();
      final data = await AppDb.instance.exportJson();
      data['gemini_api_key'] = await AiService.getKey() ?? '';
      final body = jsonEncode(data);
      final existing = await _findBackup(headers);
      final res = existing == null
          ? await _createFile(headers, body)
          : await http.patch(
              Uri.parse('$_uploadUrl/$existing?uploadType=media'),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: body,
            );
      _check(res);
      lastBackup = DateTime.now();
      await AppDb.instance
          .setSetting('last_backup_at', lastBackup!.toIso8601String());
      final tables = (data['tables'] as Map?)?.length ?? 0;
      lastMessage = 'Backed up to your Drive. $tables tables saved, including '
          'your shots, check-ins and meals.';
    });
  }

  /// Replaces local data with the cloud snapshot. Returns false if none exists.
  Future<bool> restore() async {
    var found = false;
    await _run(task: BackupTask.restore, () async {
      final headers = await _headers();
      final id = await _findBackup(headers);
      if (id == null) {
        lastMessage = 'No backup found on this account yet. Tap Back up now to '
            'make the first one.';
        return;
      }
      final res = await http.get(Uri.parse('$_filesUrl/$id?alt=media'),
          headers: headers);
      _check(res);
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      await AppDb.instance.importJson(data);
      final key = data['gemini_api_key'] as String?;
      if (key != null && key.isNotEmpty) await AiService.setKey(key);
      await ThemePrefs.load();
      await PetPrefs.load();
      final last = await AppDb.instance.getSetting('last_backup_at');
      lastBackup = last == null ? null : DateTime.tryParse(last);
      autoBackup =
          (await AppDb.instance.getSetting('auto_backup') ?? 'true') == 'true';
      await Goals.load();
      await MedPrefs.instance.load();
      final shots = await AppDb.instance.shots();
      final meals = await AppDb.instance.meals();
      final logs = await AppDb.instance.allLogs();
      lastMessage = 'Restored from your Drive backup: ${shots.length} shots, '
          '${logs.length} check-ins and ${meals.length} meals are back.';
      found = true;
    });
    return found;
  }

  // ---- helpers ----

  Future<void> _run(Future<void> Function() body,
      {BackupTask task = BackupTask.none}) async {
    this.task = task;
    busy = true;
    lastError = null;
    lastMessage = null;
    notifyListeners();
    try {
      await body();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        lastError = _explain(e);
      }
    } catch (e) {
      lastError = e.toString();
    } finally {
      busy = false;
      task = BackupTask.none;
      notifyListeners();
    }
  }

  /// Google's sign-in errors are terse and the same two causes account for
  /// nearly all of them, so name them.
  static String _explain(GoogleSignInException e) {
    final detail = e.description ?? '';
    final text = '${e.code.name} $detail'.toLowerCase();
    if (text.contains('10') || text.contains('developer')) {
      return 'Google rejected the app (DEVELOPER_ERROR). Usually the Android '
          "OAuth client is missing this build's SHA-1 fingerprint, or the ID "
          'in Settings is not the *Web application* client ID.';
    }
    if (text.contains('network')) {
      return 'No network while signing in. Try again when back online.';
    }
    if (text.contains('unsupported') || text.contains('play')) {
      return 'This device cannot run Google sign-in (Play services missing or '
          'out of date).';
    }
    return detail.isEmpty ? e.code.name : detail;
  }

  Future<Map<String, String>> _headers() async {
    if (account == null && rememberedEmail != null) await _restoreSession();
    final acct = account;
    if (acct == null) {
      throw StateError('Not connected to Google. Tap Reconnect and try again.');
    }
    final h = await acct.authorizationClient
        .authorizationHeaders(_scopes, promptIfNecessary: true);
    if (h == null) throw StateError('Drive access was not granted.');
    return h;
  }

  Future<String?> _findBackup(Map<String, String> headers) async {
    final uri = Uri.parse(_filesUrl).replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name = '$_fileName'",
      'fields': 'files(id)',
    });
    final res = await http.get(uri, headers: headers);
    _check(res);
    final files = (jsonDecode(res.body)['files'] as List?) ?? const [];
    return files.isEmpty ? null : files.first['id'] as String;
  }

  Future<http.Response> _createFile(
      Map<String, String> headers, String content) {
    const boundary = 'glpals_boundary_7f3a';
    final meta = jsonEncode({
      'name': _fileName,
      'parents': ['appDataFolder']
    });
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json\r\n\r\n$content\r\n'
        '--$boundary--';
    return http.post(
      Uri.parse('$_uploadUrl?uploadType=multipart'),
      headers: {
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary'
      },
      body: body,
    );
  }

  void _check(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Drive error ${res.statusCode}: ${res.body}');
    }
  }
}
