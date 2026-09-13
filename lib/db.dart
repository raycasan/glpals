import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Injection sites, rotated to reduce soreness. Order is the suggested rotation.
const injectionSites = [
  'Abdomen L',
  'Abdomen R',
  'Thigh L',
  'Thigh R',
  'Arm L',
  'Arm R',
];

/// Common GLP-1 side effects. Each is scored 0 (none) to 3 (severe) per day.
const sideEffectKeys = [
  'nausea',
  'fatigue',
  'constipation',
  'diarrhea',
  'appetite_loss',
  'headache',
];

class Shot {
  final int? id;
  final DateTime takenAt;
  final double doseMg;
  final String site;
  final String note;

  /// Product id this dose was taken from, so the history stays truthful after
  /// a switch. Null for shots logged before the app tracked it.
  final String? product;

  Shot({
    this.id,
    required this.takenAt,
    required this.doseMg,
    required this.site,
    this.note = '',
    this.product,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'taken_at': takenAt.toIso8601String(),
        'dose_mg': doseMg,
        'site': site,
        'note': note,
        'product': product,
      };
  static Shot fromMap(Map<String, Object?> m) => Shot(
        id: m['id'] as int?,
        takenAt: DateTime.parse(m['taken_at'] as String),
        doseMg: (m['dose_mg'] as num).toDouble(),
        site: m['site'] as String,
        note: (m['note'] as String?) ?? '',
        product: m['product'] as String?,
      );
}

/// A reminder the app put on the schedule. Rows in the past are what was
/// delivered; rows in the future are what is queued. The in-app panel reads
/// both from here, because Android does not let an app read its own posted
/// notifications back.
class NotifLog {
  final int? id;
  final DateTime at;
  final String kind; // shot, countdown, fridge, water, meal, test
  final String title;
  final String body;

  /// Set when the user acted on it from the notification itself.
  final String? action;

  NotifLog({
    this.id,
    required this.at,
    required this.kind,
    required this.title,
    required this.body,
    this.action,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'at': at.toIso8601String(),
        'kind': kind,
        'title': title,
        'body': body,
        'action': action,
      };

  static NotifLog fromMap(Map<String, Object?> m) => NotifLog(
        id: m['id'] as int?,
        at: DateTime.parse(m['at'] as String),
        kind: (m['kind'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        action: m['action'] as String?,
      );

  bool get delivered => at.isBefore(DateTime.now());
}

/// A dose the user decided not to take. Recorded so the countdown moves on
/// without a fake injection appearing in the history.
class DoseSkip {
  final int? id;
  final DateTime plannedFor;
  final DateTime skippedAt;
  final String note;

  DoseSkip({
    this.id,
    required this.plannedFor,
    required this.skippedAt,
    this.note = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'planned_for': plannedFor.toIso8601String(),
        'skipped_at': skippedAt.toIso8601String(),
        'note': note,
      };

  static DoseSkip fromMap(Map<String, Object?> m) => DoseSkip(
        id: m['id'] as int?,
        plannedFor: DateTime.parse(m['planned_for'] as String),
        skippedAt: DateTime.parse(m['skipped_at'] as String),
        note: (m['note'] as String?) ?? '',
      );
}

/// One recorded change of medication or dose. Append-only: a switch never
/// erases anything, it just starts a new chapter.
class MedChange {
  final int? id;
  final DateTime changedAt;
  final String? fromProduct;
  final double? fromDose;
  final String toProduct;
  final double toDose;
  final String note;

  MedChange({
    this.id,
    required this.changedAt,
    this.fromProduct,
    this.fromDose,
    required this.toProduct,
    required this.toDose,
    this.note = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'changed_at': changedAt.toIso8601String(),
        'from_product': fromProduct,
        'from_dose': fromDose,
        'to_product': toProduct,
        'to_dose': toDose,
        'note': note,
      };

  static MedChange fromMap(Map<String, Object?> m) => MedChange(
        id: m['id'] as int?,
        changedAt: DateTime.parse(m['changed_at'] as String),
        fromProduct: m['from_product'] as String?,
        fromDose: (m['from_dose'] as num?)?.toDouble(),
        toProduct: m['to_product'] as String,
        toDose: (m['to_dose'] as num?)?.toDouble() ?? 0,
        note: (m['note'] as String?) ?? '',
      );

  bool get isFirst => fromProduct == null;
  bool get isProductSwitch => fromProduct != null && fromProduct != toProduct;
}

class DailyLog {
  final String day; // yyyy-MM-dd, primary key
  final double? weightKg;
  final int waterMl;
  final int proteinG;
  final Map<String, int> sideEffects;
  final String note;
  DailyLog({
    required this.day,
    this.weightKg,
    this.waterMl = 0,
    this.proteinG = 0,
    Map<String, int>? sideEffects,
    this.note = '',
  }) : sideEffects = sideEffects ?? {for (final k in sideEffectKeys) k: 0};

  Map<String, Object?> toMap() => {
        'day': day,
        'weight_kg': weightKg,
        'water_ml': waterMl,
        'protein_g': proteinG,
        for (final k in sideEffectKeys) 'se_$k': sideEffects[k] ?? 0,
        'note': note,
      };
  static DailyLog fromMap(Map<String, Object?> m) => DailyLog(
        day: m['day'] as String,
        weightKg: (m['weight_kg'] as num?)?.toDouble(),
        waterMl: (m['water_ml'] as int?) ?? 0,
        proteinG: (m['protein_g'] as int?) ?? 0,
        sideEffects: {
          for (final k in sideEffectKeys) k: (m['se_$k'] as int?) ?? 0
        },
        note: (m['note'] as String?) ?? '',
      );

  int get sideEffectTotal => sideEffects.values.fold(0, (a, b) => a + b);
}

class Meal {
  final int? id;
  final DateTime eatenAt;
  final String description; // model's short name for the meal
  final String ingredients; // user-typed, optional
  final int proteinG;
  final int fiberG;
  final int calories;
  final String confidence; // low / medium / high
  final String? photoPath;
  Meal({
    this.id,
    required this.eatenAt,
    required this.description,
    this.ingredients = '',
    required this.proteinG,
    required this.fiberG,
    required this.calories,
    this.confidence = 'medium',
    this.photoPath,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'eaten_at': eatenAt.toIso8601String(),
        'description': description,
        'ingredients': ingredients,
        'protein_g': proteinG,
        'fiber_g': fiberG,
        'calories': calories,
        'confidence': confidence,
        'photo_path': photoPath,
      };
  static Meal fromMap(Map<String, Object?> m) => Meal(
        id: m['id'] as int?,
        eatenAt: DateTime.parse(m['eaten_at'] as String),
        description: m['description'] as String,
        ingredients: (m['ingredients'] as String?) ?? '',
        proteinG: (m['protein_g'] as int?) ?? 0,
        fiberG: (m['fiber_g'] as int?) ?? 0,
        calories: (m['calories'] as int?) ?? 0,
        confidence: (m['confidence'] as String?) ?? 'medium',
        photoPath: m['photo_path'] as String?,
      );
}

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      join(dir, 'glp_buddy.db'),
      version: 6,
      onUpgrade: (d, old, _) async {
        if (old < 2) await d.execute(_mealsSql);
        if (old < 3) await d.execute(_settingsSql);
        if (old < 4) {
          await _addColumn(d, 'shots', 'product', 'TEXT');
          await d.execute(_medChangesSql);
        }
        if (old < 5) await d.execute(_doseSkipsSql);
        if (old < 6) await d.execute(_notifLogSql);
      },
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE IF NOT EXISTS shots(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            taken_at TEXT NOT NULL,
            dose_mg REAL NOT NULL,
            site TEXT NOT NULL,
            note TEXT,
            product TEXT
          )''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS daily_logs(
            day TEXT PRIMARY KEY,
            weight_kg REAL,
            water_ml INTEGER DEFAULT 0,
            protein_g INTEGER DEFAULT 0,
            ${sideEffectKeys.map((k) => 'se_$k INTEGER DEFAULT 0').join(',\n')},
            note TEXT
          )''');
        await d.execute(_mealsSql);
        await d.execute(_settingsSql);
        await d.execute(_medChangesSql);
        await d.execute(_doseSkipsSql);
        await d.execute(_notifLogSql);
      },
    );
    return _db!;
  }

  /// Adds a column only when it is missing.
  ///
  /// A migration that fails partway can leave the schema changed while the
  /// recorded version stays behind, and the retry then dies on "duplicate
  /// column". Checking first makes every upgrade safe to run again.
  static Future<void> _addColumn(
      Database d, String table, String column, String type) async {
    final info = await d.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((r) => r['name'] == column);
    if (!exists) {
      await d.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  static const _medChangesSql = '''
    CREATE TABLE IF NOT EXISTS med_changes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      changed_at TEXT NOT NULL,
      from_product TEXT,
      from_dose REAL,
      to_product TEXT NOT NULL,
      to_dose REAL,
      note TEXT
    )''';

  static const _doseSkipsSql = '''
    CREATE TABLE IF NOT EXISTS dose_skips(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      planned_for TEXT NOT NULL,
      skipped_at TEXT NOT NULL,
      note TEXT
    )''';

  static const _notifLogSql = '''
    CREATE TABLE IF NOT EXISTS notif_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      at TEXT NOT NULL,
      kind TEXT,
      title TEXT,
      body TEXT,
      action TEXT
    )''';

  static const _settingsSql = '''
    CREATE TABLE IF NOT EXISTS settings(
      key TEXT PRIMARY KEY,
      value TEXT
    )''';

  // ---- Backup ----
  static const _backupTables = [
    'shots',
    'daily_logs',
    'meals',
    'settings',
    'med_changes',
    'dose_skips',
    'notif_log'
  ];

  /// Snapshot of every table as plain JSON-friendly maps.
  Future<Map<String, dynamic>> exportJson() async {
    final d = await db;
    return {
      'format': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': {for (final t in _backupTables) t: await d.query(t)},
    };
  }

  /// Replaces local tables with [data] produced by [exportJson].
  Future<void> importJson(Map<String, dynamic> data) async {
    final tables = (data['tables'] as Map?)?.cast<String, dynamic>() ?? {};
    final d = await db;
    await d.transaction((txn) async {
      for (final t in _backupTables) {
        final rows = (tables[t] as List?) ?? const [];
        await txn.delete(t);
        for (final r in rows) {
          await txn.insert(t, (r as Map).cast<String, Object?>(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  // ---- Settings (simple key/value) ----
  Future<String?> getSetting(String key) async {
    final rows =
        await (await db).query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async =>
      (await db).insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);

  static const _mealsSql = '''
    CREATE TABLE IF NOT EXISTS meals(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      eaten_at TEXT NOT NULL,
      description TEXT NOT NULL,
      ingredients TEXT,
      protein_g INTEGER DEFAULT 0,
      fiber_g INTEGER DEFAULT 0,
      calories INTEGER DEFAULT 0,
      confidence TEXT,
      photo_path TEXT
    )''';

  // ---- Meals ----
  Future<int> insertMeal(Meal m) async => (await db).insert('meals', m.toMap());
  Future<void> updateMeal(Meal m) async =>
      (await db).update('meals', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
  Future<void> deleteMeal(int id) async =>
      (await db).delete('meals', where: 'id = ?', whereArgs: [id]);
  Future<List<Meal>> meals({int? limit}) async {
    final rows =
        await (await db).query('meals', orderBy: 'eaten_at DESC', limit: limit);
    return rows.map(Meal.fromMap).toList();
  }

  Future<List<Meal>> mealsOn(String day) async {
    final rows = await (await db).query('meals',
        where: "substr(eaten_at, 1, 10) = ?",
        whereArgs: [day],
        orderBy: 'eaten_at ASC');
    return rows.map(Meal.fromMap).toList();
  }

  /// Sum of protein from logged meals for a day; used to prefill the check-in.
  Future<int> proteinOn(String day) async =>
      (await mealsOn(day)).fold<int>(0, (a, m) => a + m.proteinG);

  /// Meals eaten between two yyyy-MM-dd days, both ends included.
  Future<List<Meal>> mealsBetween(String fromDay, String toDay) async {
    final rows = await (await db).query('meals',
        where: 'substr(eaten_at, 1, 10) BETWEEN ? AND ?',
        whereArgs: [fromDay, toDay],
        orderBy: 'eaten_at ASC');
    return rows.map(Meal.fromMap).toList();
  }

  // ---- Shots ----
  Future<int> insertShot(Shot s) async => (await db).insert('shots', s.toMap());
  Future<void> deleteShot(int id) async =>
      (await db).delete('shots', where: 'id = ?', whereArgs: [id]);
  Future<List<Shot>> shots({int? limit}) async {
    final rows =
        await (await db).query('shots', orderBy: 'taken_at DESC', limit: limit);
    return rows.map(Shot.fromMap).toList();
  }

  Future<Shot?> lastShot() async => (await shots(limit: 1)).firstOrNull;

  // ---- Notification log ----
  Future<void> logNotif(NotifLog n) async =>
      (await db).insert('notif_log', n.toMap());

  /// Clears queued (future) entries before a fresh schedule is written, so the
  /// panel never shows reminders that were replaced. History is untouched.
  Future<void> clearQueuedNotifs() async => (await db).delete('notif_log',
      where: 'at > ?', whereArgs: [DateTime.now().toIso8601String()]);

  Future<List<NotifLog>> notifs({int limit = 120}) async {
    final rows =
        await (await db).query('notif_log', orderBy: 'at DESC', limit: limit);
    return rows.map(NotifLog.fromMap).toList();
  }

  /// Marks the most recent delivered reminder of a kind as acted on.
  Future<void> markNotifAction(String kind, String action) async {
    final d = await db;
    final rows = await d.query('notif_log',
        where: 'kind = ? AND at <= ?',
        whereArgs: [kind, DateTime.now().toIso8601String()],
        orderBy: 'at DESC',
        limit: 1);
    if (rows.isEmpty) return;
    await d.update('notif_log', {'action': action},
        where: 'id = ?', whereArgs: [rows.first['id']]);
  }

  Future<void> clearNotifHistory() async => (await db).delete('notif_log',
      where: 'at <= ?', whereArgs: [DateTime.now().toIso8601String()]);

  // ---- Skipped doses ----
  Future<int> insertSkip(DoseSkip s) async =>
      (await db).insert('dose_skips', s.toMap());

  Future<void> deleteSkip(int id) async =>
      (await db).delete('dose_skips', where: 'id = ?', whereArgs: [id]);

  Future<List<DoseSkip>> skips() async {
    final rows =
        await (await db).query('dose_skips', orderBy: 'planned_for DESC');
    return rows.map(DoseSkip.fromMap).toList();
  }

  Future<DoseSkip?> lastSkip() async => (await skips()).firstOrNull;

  Future<List<DoseSkip>> skipsBetween(String fromDay, String toDay) async {
    final rows = await (await db).query('dose_skips',
        where: 'substr(planned_for, 1, 10) BETWEEN ? AND ?',
        whereArgs: [fromDay, toDay],
        orderBy: 'planned_for ASC');
    return rows.map(DoseSkip.fromMap).toList();
  }

  // ---- Medication history ----
  Future<int> insertMedChange(MedChange c) async =>
      (await db).insert('med_changes', c.toMap());

  /// Newest first.
  Future<List<MedChange>> medChanges() async {
    final rows =
        await (await db).query('med_changes', orderBy: 'changed_at DESC');
    return rows.map(MedChange.fromMap).toList();
  }

  /// Shots taken between two yyyy-MM-dd days, both ends included.
  Future<List<Shot>> shotsBetween(String fromDay, String toDay) async {
    final rows = await (await db).query('shots',
        where: 'substr(taken_at, 1, 10) BETWEEN ? AND ?',
        whereArgs: [fromDay, toDay],
        orderBy: 'taken_at ASC');
    return rows.map(Shot.fromMap).toList();
  }

  /// Next site in rotation after the last shot.
  Future<String> suggestedSite() async {
    final last = await lastShot();
    if (last == null) return injectionSites.first;
    final i = injectionSites.indexOf(last.site);
    return injectionSites[(i + 1) % injectionSites.length];
  }

  // ---- Daily logs ----
  Future<void> upsertLog(DailyLog l) async =>
      (await db).insert('daily_logs', l.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<DailyLog?> logFor(String day) async {
    final rows = await (await db)
        .query('daily_logs', where: 'day = ?', whereArgs: [day]);
    return rows.isEmpty ? null : DailyLog.fromMap(rows.first);
  }

  /// Daily logs between two yyyy-MM-dd days, both ends included.
  Future<List<DailyLog>> logsBetween(String fromDay, String toDay) async {
    final rows = await (await db).query('daily_logs',
        where: 'day BETWEEN ? AND ?',
        whereArgs: [fromDay, toDay],
        orderBy: 'day ASC');
    return rows.map(DailyLog.fromMap).toList();
  }

  /// Every daily log, oldest first. Used by the experience calculation.
  Future<List<DailyLog>> allLogs() async {
    final rows = await (await db).query('daily_logs', orderBy: 'day ASC');
    return rows.map(DailyLog.fromMap).toList();
  }

  Future<List<DailyLog>> logs({int days = 90}) async {
    final rows =
        await (await db).query('daily_logs', orderBy: 'day ASC', limit: days);
    return rows.map(DailyLog.fromMap).toList();
  }

  /// Consecutive days (ending today or yesterday) with a saved log.
  Future<int> streak() async {
    final all = await (await db).query('daily_logs', columns: ['day']);
    final days = all.map((r) => r['day'] as String).toSet();
    var d = DateTime.now();
    var count = 0;
    String key(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    if (!days.contains(key(d))) d = d.subtract(const Duration(days: 1));
    while (days.contains(key(d))) {
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }
}
