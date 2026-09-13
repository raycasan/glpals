import 'package:flutter/material.dart';

import 'db.dart';

/// Current theme mode. Change via [ThemePrefs.set]; the app rebuilds automatically.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

class ThemePrefs {
  static const _key = 'theme_mode';

  static Future<void> load() async {
    final v = await AppDb.instance.getSetting(_key);
    themeMode.value = ThemeMode.values
        .firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
  }

  static Future<void> set(ThemeMode m) async {
    themeMode.value = m;
    await AppDb.instance.setSetting(_key, m.name);
  }
}

/// Default daily goals. [Goals] holds the personalized values actually used.
const kWaterGoalMl = 2000;
const kGlassMl = 250;
const kProteinGoalG = 100;
const kFiberGoalG = 25;

/// Daily targets that drive every ring, bar and reminder.
///
/// Set during onboarding from body weight and the chosen medication, and
/// editable afterwards. Values live in the settings table, so a restored
/// backup brings them back.
class Goals {
  static int proteinG = kProteinGoalG;
  static int waterMl = kWaterGoalMl;
  static int fiberG = kFiberGoalG;

  /// Daily energy target in kcal. Zero means no target: calories are still
  /// totalled and shown, there is just nothing to fall short of.
  ///
  /// Unlike the others this is never suggested by the app or the assistant.
  /// Protein, fibre and fluid are the numbers worth chasing on a GLP-1, and a
  /// prescribed calorie figure is a conversation for a clinician, so the user
  /// types this one themselves or leaves it off.
  static int caloriesKcal = 0;

  static bool get hasCalorieTarget => caloriesKcal > 0;

  /// Bumped on every change so screens can rebuild.
  static final revision = ValueNotifier<int>(0);

  static Future<void> load() async {
    final db = AppDb.instance;
    Future<int> g(String k, int def) async =>
        int.tryParse(await db.getSetting(k) ?? '') ?? def;
    proteinG = await g('goal_protein_g', kProteinGoalG);
    waterMl = await g('goal_water_ml', kWaterGoalMl);
    fiberG = await g('goal_fiber_g', kFiberGoalG);
    caloriesKcal = await g('goal_calories_kcal', 0);
    revision.value++;
  }

  static Future<void> set(
      {int? protein, int? water, int? fiber, int? calories}) async {
    final db = AppDb.instance;
    if (protein != null) {
      proteinG = protein.clamp(20, 400);
      await db.setSetting('goal_protein_g', '$proteinG');
    }
    if (water != null) {
      waterMl = water.clamp(500, 6000);
      await db.setSetting('goal_water_ml', '$waterMl');
    }
    if (fiber != null) {
      fiberG = fiber.clamp(5, 80);
      await db.setSetting('goal_fiber_g', '$fiberG');
    }
    if (calories != null) {
      caloriesKcal = calories <= 0 ? 0 : calories.clamp(800, 6000);
      await db.setSetting('goal_calories_kcal', '$caloriesKcal');
    }
    revision.value++;
  }

  /// How much someone moves, which shifts the protein target.
  static const activities = ['sedentary', 'light', 'active'];

  /// Grams of protein per kg of body weight for each activity level. Protein
  /// is the number that matters most while appetite is suppressed, so it is
  /// the one that scales.
  static const _proteinPerKg = {
    'sedentary': 1.2,
    'light': 1.4,
    'active': 1.6,
  };

  /// Sensible starting targets for a body weight, used when the AI plan is
  /// unavailable: protein by activity, and about 33 ml of fluid per kg.
  static ({int protein, int water, int fiber}) suggestFor(
    double? weightKg, {
    String activity = 'light',
  }) {
    if (weightKg == null || weightKg <= 0) {
      return (protein: kProteinGoalG, water: kWaterGoalMl, fiber: kFiberGoalG);
    }
    final perKg = _proteinPerKg[activity] ?? 1.4;
    final protein = (weightKg * perKg).round().clamp(60, 220);
    final water = ((weightKg * 33) / 250).round() * 250;
    return (
      protein: protein,
      water: water.clamp(1500, 4000),
      fiber: activity == 'active' ? 30 : 25,
    );
  }
}

/// How the home-screen widget looks.
///
/// Simple drops everything but the two rings you act on daily and makes them
/// large; detailed keeps the dose block and the day's chips. Text size is
/// separate, because someone may want all the detail and still need it bigger.
class WidgetPrefs {
  static const styles = ['simple', 'detailed'];
  static const textSizes = ['normal', 'large', 'xlarge'];

  static String style = 'detailed';
  static String textSize = 'normal';

  static final revision = ValueNotifier<int>(0);

  static String labelFor(String size) => switch (size) {
        'large' => 'Large',
        'xlarge' => 'Extra large',
        _ => 'Normal',
      };

  static Future<void> load() async {
    final db = AppDb.instance;
    style = await db.getSetting('widget_style') ?? 'detailed';
    textSize = await db.getSetting('widget_text') ?? 'normal';
    revision.value++;
  }

  static Future<void> set({String? style, String? textSize}) async {
    final db = AppDb.instance;
    if (style != null) {
      WidgetPrefs.style = style;
      await db.setSetting('widget_style', style);
    }
    if (textSize != null) {
      WidgetPrefs.textSize = textSize;
      await db.setSetting('widget_text', textSize);
    }
    revision.value++;
  }
}

/// Playful brand palette.
class Palette {
  static const coral = Color(0xFFFF7B54);
  static const peach = Color(0xFFFFB26B);
  static const mint = Color(0xFF2EC4B6);
  static const sky = Color(0xFF4CC9F0);
  static const lavender = Color(0xFF9B8CFF);
  static const sunshine = Color(0xFFFFD166);
  static const berry = Color(0xFFEF476F);
  static const cream = Color(0xFFFFF8F2);
  static const ink = Color(0xFF2B2D42);

  static const sunset = LinearGradient(
    colors: [Color(0xFFFF7B54), Color(0xFFFFB26B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const ocean = LinearGradient(
    colors: [Color(0xFF2EC4B6), Color(0xFF4CC9F0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const grape = LinearGradient(
    colors: [Color(0xFF9B8CFF), Color(0xFFC77DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: Palette.coral,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    ).copyWith(
      primary: dark ? Palette.peach : Palette.coral,
      onPrimary: dark ? Palette.ink : Colors.white,
      secondary: Palette.mint,
      tertiary: Palette.lavender,
      surface: dark ? const Color(0xFF17182B) : Palette.cream,
      onSurface: dark ? const Color(0xFFF2F0FF) : Palette.ink,
    );
    final cardColor = dark ? const Color(0xFF232538) : Colors.white;
    final fieldColor = dark ? const Color(0xFF2B2D45) : Colors.white;
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme;
    TextStyle? bold(TextStyle? s, [double spacing = -0.3]) =>
        s?.copyWith(fontWeight: FontWeight.w800, letterSpacing: spacing);

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        displaySmall: bold(text.displaySmall, -1),
        headlineMedium: bold(text.headlineMedium, -0.5),
        headlineSmall: bold(text.headlineSmall, -0.5),
        titleLarge: bold(text.titleLarge),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          side: BorderSide(
              color: scheme.primary.withValues(alpha: .5), width: 1.5),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: border(Colors.transparent),
        enabledBorder: border(scheme.outlineVariant.withValues(alpha: .5)),
        focusedBorder: border(scheme.primary, 2),
        labelStyle: TextStyle(
            color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        hintStyle:
            TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: .7)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        elevation: 0,
        height: 72,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: .16),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12.5,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: s.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        shape: const StadiumBorder(),
        extendedTextStyle:
            const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Palette.ink,
        contentTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      dividerTheme:
          DividerThemeData(color: scheme.outlineVariant.withValues(alpha: .4)),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: .12),
      ),
    );
  }
}
