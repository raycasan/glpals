import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import 'ai_service.dart';
import 'db.dart';
import 'med.dart';
import 'reminders.dart';
import 'theme.dart';
import 'widget_bridge.dart';
import 'widgets/pet.dart';

/// Entry point for notification action buttons while the app is in the
/// background or closed. Runs in its own isolate.
@pragma('vm:entry-point')
void notificationActionBackground(NotificationResponse response) {
  DartPluginRegistrant.ensureInitialized();
  NotificationActions.handle(response, background: true);
}

/// Applies what the user did on a notification: log water, log a shot, type
/// a meal, snooze, or skip. Works from the foreground and background alike.
class NotificationActions {
  static Future<void> handle(NotificationResponse r,
      {bool background = false}) async {
    final action = r.actionId;
    if (action == null || action.isEmpty) return;
    final db = AppDb.instance;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final payload = r.payload ?? '';
    var snoozeShot = false;
    debugPrint(
        'GLPals action: $action payload=$payload background=$background');

    // The database has to be reachable before anything is written; in the
    // background isolate the plugins are registered by the entry point above.
    try {
      if (action.startsWith('water_')) {
        final glasses = int.tryParse(action.substring(6)) ?? 1;
        final log = await db.logFor(today);
        await db.upsertLog(DailyLog(
          day: today,
          weightKg: log?.weightKg,
          waterMl: (log?.waterMl ?? 0) + glasses * kGlassMl,
          proteinG: log?.proteinG ?? 0,
          sideEffects: log?.sideEffects,
          note: log?.note ?? '',
        ));
      } else if (action == 'shot_now') {
        final last = await db.lastShot();
        final site = await db.suggestedSite();
        await db.insertShot(Shot(
          takenAt: now,
          doseMg: last?.doseMg ?? 0,
          site: site,
          note: 'Logged from notification',
        ));
      } else if (action == 'shot_snooze') {
        snoozeShot = true;
      } else if (action == 'meal_text') {
        final text = (r.input ?? '').trim();
        if (text.isNotEmpty) await _logMealFromText(text, payload);
      } else if (action == 'meal_skip') {
        final slot = payload.startsWith('meal:') ? payload.substring(5) : '';
        if (slot.isNotEmpty) {
          await db.setSetting('rem_meal_${slot}_skip', today);
        }
      }
    } catch (e, st) {
      debugPrint('GLPals action failed: $e');
      debugPrintStack(stackTrace: st);
    }

    // Remember what was tapped so the in-app panel can show it.
    try {
      await db.markNotifAction(
          payload.split(':').first, action.replaceAll('_', ' '));
    } catch (_) {}

    if (background) {
      await Reminders.initBackground();
      await PetPrefs.load();
      await Goals.load();
      await MedPrefs.instance.load();
    }
    await Reminders.sync();
    if (snoozeShot) await Reminders.snoozeShot();
    await HomeWidgetBridge.update();
  }

  /// Saves the typed meal right away, then tries a quick nutrition estimate
  /// with Gemini when an API key is available. Falls back to a manual entry.
  static Future<void> _logMealFromText(String text, String payload) async {
    final db = AppDb.instance;
    final slot = payload.startsWith('meal:') ? payload.substring(5) : '';
    final slotLabel =
        MealSlot.all.where((m) => m.id == slot).map((m) => m.label).firstOrNull;
    var description = slotLabel == null ? text : '$slotLabel: $text';
    var protein = 0, fiber = 0, calories = 0;
    var confidence = 'manual';
    final hasKey = (await AiService.getKey() ?? '').isNotEmpty;
    if (hasKey) {
      try {
        final r = await AiService.analyzeMeal(
          imageBytes: null,
          mimeType: 'image/jpeg',
          ingredients: text,
        ).timeout(const Duration(seconds: 25));
        description = r['description']?.toString() ?? description;
        protein = (r['protein_g'] as num?)?.toInt() ?? 0;
        fiber = (r['fiber_g'] as num?)?.toInt() ?? 0;
        calories = (r['calories'] as num?)?.toInt() ?? 0;
        confidence = r['confidence']?.toString() ?? 'low';
      } catch (_) {
        // Keep the manual entry; the user can edit it in the app.
      }
    }
    await db.insertMeal(Meal(
      eatenAt: DateTime.now(),
      description: description,
      ingredients: text,
      proteinG: protein,
      fiberG: fiber,
      calories: calories,
      confidence: confidence,
      photoPath: null,
    ));
  }
}
