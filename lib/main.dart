import 'dart:async';

import 'package:flutter/material.dart';

import 'backup_service.dart';
import 'db.dart';
import 'live_activity.dart';
import 'med.dart';
import 'reminders.dart';
import 'screens/assistant_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/checkin_screen.dart';
import 'screens/food_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shot_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/trends_screen.dart';
import 'theme.dart';
import 'widget_bridge.dart';
import 'widgets/nav_bar.dart';
import 'widgets/pet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The branded splash draws immediately; startup work runs behind it.
  runApp(const GlpBuddyApp());
}

/// Startup steps, run behind the splash. Each is guarded: a misbehaving
/// plugin must never keep the app stuck. Returns true on the first launch,
/// when setup has not been completed yet.
Future<bool> _startup() async {
  await _guard(Goals.load);
  await _guard(WidgetPrefs.load);
  await _guard(MedPrefs.instance.load);
  await _guard(Profile.instance.load);
  // Reminders.init ends with a sync, and that sync also refreshes the Dynamic
  // Island, so everything the island reads has to be loaded before it: with
  // LiveActivityPrefs still at its default (off) it would end the activity on
  // every launch, and with PetPrefs unloaded it would show the wrong pal.
  await _guard(PetPrefs.load);
  await _guard(LiveActivityPrefs.load);
  await _guard(Reminders.init);
  await _guard(ThemePrefs.load);
  await _guard(BackupService.instance.init);
  var firstRun = true;
  await _guard(() async {
    final db = AppDb.instance;
    // 'onboarded' is set by the setup flow; an existing install that only ever
    // picked a pal counts as done so it is not asked again.
    firstRun = await db.getSetting('onboarded') == null &&
        await db.getSetting('pet_species') == null;
  });
  return firstRun;
}

Future<void> _guard(Future<void> Function() step) async {
  try {
    await step();
  } catch (e, st) {
    debugPrint('Startup step failed: $e');
    debugPrintStack(stackTrace: st);
  }
}

class GlpBuddyApp extends StatelessWidget {
  const GlpBuddyApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (_, mode, __) => MaterialApp(
          title: 'GLPals',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: SplashScreen<bool>(
            init: _startup,
            next: (firstRun) => _Root(firstRun: firstRun),
          ),
        ),
      );
}

/// Onboarding on the first launch, the tab shell afterwards.
class _Root extends StatefulWidget {
  const _Root({required this.firstRun});
  final bool firstRun;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late bool _showOnboarding = widget.firstRun;

  @override
  Widget build(BuildContext context) => _showOnboarding
      ? OnboardingScreen(onDone: () => setState(() => _showOnboarding = false))
      : const Shell();
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _foodKey = GlobalKey<FoodScreenState>();

  static const _titles = [
    'GLPals',
    'Shots',
    'Check-in',
    'Meals',
    'Trends',
    'Buddy chat'
  ];
  static const _emoji = ['🐠', '💉', '📝', '🍽️', '📈', '💬'];

  void _go(int i) {
    setState(() => _tab = i);
    if (i == 0) _homeKey.currentState?.refresh();
  }

  @override
  void initState() {
    super.initState();
    Reminders.onChanged = () => _homeKey.currentState?.refresh();
    HomeWidgetBridge.update();
  }

  /// Called after any save: refresh Home and queue a cloud backup if enabled.
  void _onSaved() {
    _homeKey.currentState?.refresh();
    BackupService.instance.scheduleAutoBackup();
    Reminders.sync();
    HomeWidgetBridge.update();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        key: _homeKey,
        onLogShot: () => _go(1),
        onCheckIn: () => _go(2),
        onLogMeal: () => _go(3),
        onAsk: () => _go(5),
      ),
      ShotScreen(onSaved: _onSaved),
      CheckInScreen(onSaved: _onSaved),
      FoodScreen(key: _foodKey, onSaved: _onSaved),
      const TrendsScreen(),
      AssistantScreen(onOpenSettings: () => _openSettings(context)),
    ];
    // Back from any tab returns to Home first; only Home lets the app close.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              if (_tab == 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset('assets/icon/glpals_icon_512.png',
                      width: 26, height: 26, filterQuality: FilterQuality.high),
                )
              else
                Text(_emoji[_tab], style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(_titles[_tab]),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              tooltip: 'Reminders',
              style: IconButton.styleFrom(
                backgroundColor: Palette.mint.withValues(alpha: .18),
                foregroundColor: Palette.mint,
              ),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NotificationsScreen())),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.calendar_month_rounded),
              tooltip: 'Calendar',
              style: IconButton.styleFrom(
                backgroundColor: Palette.lavender.withValues(alpha: .18),
                foregroundColor: Palette.lavender,
              ),
              onPressed: _openCalendar,
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Settings',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .16),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () => _openSettings(context),
              ),
            ),
          ],
        ),
        body: IndexedStack(index: _tab, children: pages),
        bottomNavigationBar: GlpalsNavBar(
          index: _tab,
          onTap: _go,
          items: const [
            NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
                color: Palette.coral),
            NavItem(
                icon: Icons.vaccines_outlined,
                activeIcon: Icons.vaccines_rounded,
                label: 'Shots',
                color: Palette.berry),
            NavItem(
                icon: Icons.task_alt_outlined,
                activeIcon: Icons.task_alt_rounded,
                label: 'Check-in',
                color: Palette.mint),
            NavItem(
                icon: Icons.restaurant_outlined,
                activeIcon: Icons.restaurant_rounded,
                label: 'Meals',
                color: Palette.sunshine),
            NavItem(
                icon: Icons.insights_outlined,
                activeIcon: Icons.insights_rounded,
                label: 'Trends',
                color: Palette.sky),
            NavItem(
                icon: Icons.forum_outlined,
                activeIcon: Icons.forum_rounded,
                label: 'Buddy',
                color: Palette.lavender),
          ],
        ),
      ),
    );
  }

  /// Month view for looking back. Reachable from every tab.
  Future<void> _openCalendar() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CalendarScreen(onChanged: _onSaved),
    ));
    _foodKey.currentState?.refresh();
    _homeKey.currentState?.refresh();
  }

  /// Settings live on their own screen: one page per topic, so nothing is
  /// buried in a long sheet.
  Future<void> _openSettings(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(onChanged: _onSaved),
    ));
    if (mounted) setState(() {});
  }
}
