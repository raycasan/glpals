import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ai_service.dart';
import '../backup_service.dart';
import '../db.dart';
import '../med.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widget_bridge.dart';
import '../widgets/backup_section.dart';
import '../widgets/common.dart';
import '../widgets/pal_evolution.dart';
import '../widgets/pet.dart';
import '../xp.dart';
import 'onboarding_screen.dart';
import 'reminder_settings.dart';

/// Settings hub.
///
/// One screen per topic rather than one long sheet: each row says what it
/// controls and what it is set to now, so the current state is readable
/// without opening anything.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onChanged});

  /// Called when something that affects the rest of the app changed.
  final VoidCallback? onChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showAdvanced = false;

  Future<void> _open(String title, Widget body) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SettingsPage(title: title, child: body),
    ));
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          // Developer bits stay out of the way behind a long press.
          onLongPress: () => setState(() => _showAdvanced = !_showAdvanced),
          child: const Text('Settings ⚙️'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          ValueListenableBuilder<PetSpecies>(
            valueListenable: petSpecies,
            builder: (_, species, __) => _SettingsRow(
              emoji: species.icon,
              color: Palette.coral,
              title: 'Your companion',
              value: species.name,
              onTap: () => _open('Your companion', const CompanionPage()),
            ),
          ),
          ListenableBuilder(
            listenable: Profile.instance,
            builder: (_, __) => _SettingsRow(
              emoji: '🎯',
              color: Palette.mint,
              title: 'You and your targets',
              value: '${Goals.proteinG} g protein · ${Goals.waterMl} ml water',
              onTap: () => _open('You and your targets', const TargetsPage()),
            ),
          ),
          ListenableBuilder(
            listenable: MedPrefs.instance,
            builder: (_, __) => _SettingsRow(
              emoji: MedPrefs.instance.product.emoji,
              color: Palette.berry,
              title: 'Medication',
              value: '${MedPrefs.instance.product.brand} · '
                  '${fmtDose(MedPrefs.instance.doseMg)} mg',
              onTap: () => _open('Medication', const MedicationPage()),
            ),
          ),
          ListenableBuilder(
            listenable: ReminderPrefs.instance,
            builder: (_, __) => _SettingsRow(
              emoji: '🔔',
              color: Palette.sunshine,
              title: 'Reminders',
              value: _reminderSummary(),
              onTap: () =>
                  _open('Reminders', RemindersPage(showChime: _showAdvanced)),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: WidgetPrefs.revision,
            builder: (_, __, ___) => _SettingsRow(
              emoji: '📱',
              color: Palette.sky,
              title: 'Home screen widget',
              value: '${WidgetPrefs.style == 'simple' ? 'Simple' : 'Detailed'}'
                  ' · ${WidgetPrefs.labelFor(WidgetPrefs.textSize)} text',
              onTap: () => _open('Home screen widget', const WidgetPage()),
            ),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeMode,
            builder: (_, mode, __) => _SettingsRow(
              emoji: switch (mode) {
                ThemeMode.light => '☀️',
                ThemeMode.dark => '🌙',
                _ => '📱',
              },
              color: Palette.lavender,
              title: 'Appearance',
              value: switch (mode) {
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
                _ => 'Follow the phone',
              },
              onTap: () => _open('Appearance', const AppearancePage()),
            ),
          ),
          ListenableBuilder(
            listenable: BackupService.instance,
            builder: (_, __) {
              final svc = BackupService.instance;
              return _SettingsRow(
                emoji: '☁️',
                color: Palette.peach,
                title: 'Backup & sync',
                value: switch (svc.link) {
                  GoogleLink.unconfigured => 'Needs a client ID',
                  GoogleLink.signedOut => 'Not signed in',
                  GoogleLink.restoring => 'Reconnecting…',
                  GoogleLink.needsReconnect => 'Tap to reconnect',
                  GoogleLink.connected => svc.lastBackup == null
                      ? 'Connected, no backup yet'
                      : 'Last backup ${relativeDay(svc.lastBackup!)}',
                },
                onTap: () => _open('Backup & sync', const BackupPage()),
              );
            },
          ),
          if (_showAdvanced)
            _SettingsRow(
              emoji: '🛠️',
              color: Palette.ink,
              title: 'Advanced',
              value: 'API key, setup, chime test',
              onTap: () => _open('Advanced', const AdvancedPage()),
            ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'GLPals is a tracker, not medical advice.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  String _reminderSummary() {
    final p = ReminderPrefs.instance;
    final on = <String>[
      if (p.shotOn) 'shot',
      if (p.countdownOn) 'countdown',
      if (p.waterOn) 'water',
      if (p.mealOn.values.any((v) => v)) 'meals',
    ];
    return on.isEmpty ? 'All off' : '${on.join(', ')} on';
  }
}

/// One row in the hub: what it is, what it is set to, and a way in.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.emoji,
    required this.color,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String emoji;
  final Color color;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color.withValues(alpha: .16)),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Shared frame for every settings sub-page.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [child],
        ),
      );
}

/// Small helper for the explanatory line under a page title.
class _Intro extends StatelessWidget {
  const _Intro(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text,
            style: TextStyle(
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

// ---------------------------------------------------------------- companion

class CompanionPage extends StatefulWidget {
  const CompanionPage({super.key});
  @override
  State<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends State<CompanionPage> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PetSpecies>(
      valueListenable: petSpecies,
      builder: (context, current, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Intro(
              'Your pal levels up as you log and hit your goals. Swapping keeps '
              'all your experience.'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              for (final s in PetSpecies.all)
                _ChoiceTile(
                  emoji: s.icon,
                  label: s.name,
                  selected: current.id == s.id,
                  onTap: () async {
                    await PetPrefs.set(s);
                    await HomeWidgetBridge.update();
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionTitle('How it grows', emoji: '⭐'),
          FutureBuilder<XpSummary>(
            future: Xp.compute(),
            builder: (_, snap) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PalEvolution(species: current, xp: snap.data?.total ?? 0),
                const SizedBox(height: 10),
                Text('${snap.data?.total ?? 0} XP so far',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ targets

class TargetsPage extends StatefulWidget {
  const TargetsPage({super.key});
  @override
  State<TargetsPage> createState() => _TargetsPageState();
}

class _TargetsPageState extends State<TargetsPage> {
  final _weight = TextEditingController();
  final _goal = TextEditingController();
  final _height = TextEditingController();
  final _calories = TextEditingController();
  bool _asking = false;
  String? _aiError;
  List<String> _tips = const [];

  @override
  void initState() {
    super.initState();
    final p = Profile.instance;
    if (p.weightKg != null) _weight.text = fmtDose(p.weightKg!);
    if (p.goalWeightKg != null) _goal.text = fmtDose(p.goalWeightKg!);
    if (p.heightCm != null) _height.text = fmtDose(p.heightCm!);
    if (Goals.hasCalorieTarget) _calories.text = '${Goals.caloriesKcal}';
  }

  @override
  void dispose() {
    _weight.dispose();
    _goal.dispose();
    _height.dispose();
    _calories.dispose();
    super.dispose();
  }

  double? get _w => double.tryParse(_weight.text.trim());

  ({int protein, int water, int fiber}) get _suggested =>
      Goals.suggestFor(_w, activity: Profile.instance.activity);

  Future<void> _saveProfile() async {
    await Profile.instance.save(
      weightKg: _w,
      goalWeightKg: double.tryParse(_goal.text.trim()),
      heightCm: double.tryParse(_height.text.trim()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _applySuggested() async {
    await _saveProfile();
    final s = _suggested;
    await Goals.set(protein: s.protein, water: s.water, fiber: s.fiber);
    await HomeWidgetBridge.update();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Targets set: ${s.protein} g protein, ${s.water} ml water, '
          '${s.fiber} g fiber.'),
    ));
  }

  Future<void> _saveCalories() async {
    final raw = _calories.text.trim();
    await Goals.set(calories: raw.isEmpty ? 0 : int.tryParse(raw) ?? 0);
    await HomeWidgetBridge.update();
    if (!mounted) return;
    setState(() {});
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(Goals.hasCalorieTarget
          ? 'Energy target set to ${Goals.caloriesKcal} kcal a day.'
          : 'Energy target cleared. Calories are still totalled each day.'),
    ));
  }

  Future<void> _askAi() async {
    await _saveProfile();
    setState(() {
      _asking = true;
      _aiError = null;
    });
    try {
      final med = MedPrefs.instance;
      final p = Profile.instance;
      final r = await AiService.onboardingPlan(
        product: med.product.brand,
        molecule: med.product.molecule,
        schedule: med.product.schedule.label,
        doseMg: med.doseMg,
        weightKg: p.weightKg,
        goalWeightKg: p.goalWeightKg,
        heightCm: p.heightCm,
      );
      await Goals.set(
        protein: (r['protein_g'] as num?)?.toInt(),
        water: (r['water_ml'] as num?)?.toInt(),
        fiber: (r['fiber_g'] as num?)?.toInt(),
      );
      await HomeWidgetBridge.update();
      if (!mounted) return;
      setState(() => _tips = (r['tips'] as List?)?.cast<String>() ?? const []);
    } catch (e) {
      if (mounted) setState(() => _aiError = AiException.from(e).message);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = Profile.instance;
    final s = _suggested;
    final matches = s.protein == Goals.proteinG &&
        s.water == Goals.waterMl &&
        s.fiber == Goals.fiberG;

    return ListenableBuilder(
      listenable: p,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Intro(
              'Protein and fluid targets are sized from your weight, which '
              'stays up to date from your check-ins.'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  onEditingComplete: _saveProfile,
                  decoration: const InputDecoration(
                      labelText: 'Weight', suffixText: 'kg'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _goal,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  onEditingComplete: _saveProfile,
                  decoration: const InputDecoration(
                      labelText: 'Goal', suffixText: 'kg'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _height,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            onEditingComplete: _saveProfile,
            decoration:
                const InputDecoration(labelText: 'Height', suffixText: 'cm'),
          ),
          const SizedBox(height: 18),
          const SectionTitle('How active are you?', emoji: '🏃'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in Goals.activities)
                Pill(
                  label: a,
                  color: Palette.mint,
                  selected: p.activity == a,
                  onTap: () async {
                    await Profile.instance.save(activity: a);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
          if (p.bmi != null || p.toGoalKg != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (p.bmi != null)
                  Pill(
                      label: 'BMI ${p.bmi!.toStringAsFixed(1)}',
                      emoji: '⚖️',
                      color: Palette.lavender),
                if (p.toGoalKg != null && p.toGoalKg! > 0)
                  Pill(
                      label: '${p.toGoalKg!.toStringAsFixed(1)} kg to goal',
                      emoji: '🎯',
                      color: Palette.peach),
                if (p.toGoalKg != null && p.toGoalKg! <= 0)
                  const Pill(
                      label: 'Goal reached', emoji: '🏆', color: Palette.mint),
              ],
            ),
          ],
          const SizedBox(height: 22),
          const SectionTitle('Daily targets', emoji: '🥗'),
          SoftCard(
            color: Palette.mint.withValues(alpha: .12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _w == null
                      ? 'Add your weight and these can be sized for you.'
                      : 'Suggested for ${fmtDose(_w!)} kg, ${p.activity}.',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _TargetChip(
                        label: 'Protein',
                        value: '${s.protein} g',
                        now: Goals.proteinG,
                        next: s.protein,
                        color: Palette.mint),
                    const SizedBox(width: 8),
                    _TargetChip(
                        label: 'Water',
                        value: '${s.water} ml',
                        now: Goals.waterMl,
                        next: s.water,
                        color: Palette.sky),
                    const SizedBox(width: 8),
                    _TargetChip(
                        label: 'Fiber',
                        value: '${s.fiber} g',
                        now: Goals.fiberG,
                        next: s.fiber,
                        color: Palette.peach),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _w == null || matches ? null : _applySuggested,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(matches && _w != null
                      ? 'These are in use'
                      : 'Use these targets'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _asking ? null : _askAi,
                  icon: _asking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_asking
                      ? 'Asking your buddy…'
                      : 'Have your buddy size them'),
                ),
                if (_aiError != null) ...[
                  const SizedBox(height: 10),
                  Text(_aiError!,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Palette.berry)),
                ],
                if (_tips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final t in _tips.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(
                            child: Text(t,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: scheme.onSurface)),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Energy', emoji: '🔥'),
          SoftCard(
            color: Palette.coral.withValues(alpha: .12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Calories from your meals are added up every day whether or '
                  'not you set a target here.',
                  style: TextStyle(
                      fontSize: 13, height: 1.4, color: scheme.onSurface),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _calories,
                  keyboardType: TextInputType.number,
                  onEditingComplete: _saveCalories,
                  decoration: const InputDecoration(
                    labelText: 'Daily energy target',
                    suffixText: 'kcal',
                    hintText: 'Leave blank to just track',
                    prefixIcon: Icon(Icons.local_fire_department_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _saveCalories,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Save'),
                      ),
                    ),
                    if (Goals.hasCalorieTarget) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _calories.clear();
                            _saveCalories();
                          },
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          label: const Text('Clear'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'This one is yours to set. The app and the assistant will '
                  'not suggest a number: on a GLP-1 the useful targets are '
                  'protein, fibre and fluid, and a calorie figure is worth '
                  'agreeing with your prescriber.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.value,
    required this.now,
    required this.next,
    required this.color,
  });
  final String label;
  final String value;
  final int now;
  final int next;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final changed = now != next;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14, color: color)),
            const SizedBox(height: 3),
            Text(changed ? '$label · now $now' : label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- medication

class MedicationPage extends StatefulWidget {
  const MedicationPage({super.key});
  @override
  State<MedicationPage> createState() => _MedicationPageState();
}

class _MedicationPageState extends State<MedicationPage> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final med = MedPrefs.instance;
    return ListenableBuilder(
      listenable: med,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Intro(
              'This sets your dose interval, the countdown and the forecast. '
              "Dose changes are your prescriber's call."),
          DropdownButtonFormField<String>(
            initialValue: med.product.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product'),
            items: [
              for (final p in GlpProduct.all)
                DropdownMenuItem(
                  value: p.id,
                  child: Text('${p.emoji}  ${p.brand}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) async {
              final next = GlpProduct.byId(id);
              if (next.id == med.product.id) return;
              final ok = await confirmProductSwitch(context, med.product, next);
              if (!ok) return;
              final was = med.product.brand;
              await med.save(
                product: next,
                doseMg: next.doses.first,
                note: 'Switched from $was',
              );
              await Reminders.sync();
              await HomeWidgetBridge.update();
            },
          ),
          const SizedBox(height: 8),
          Text(
              '${med.product.subtitle} · every ${med.intervalDays} day'
              '${med.intervalDays == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          const SectionTitle('Your dose', emoji: '⚖️'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in med.product.doses)
                Pill(
                  label: '${fmtDose(d)} mg',
                  color: Palette.coral,
                  selected: d == med.doseMg,
                  onTap: () async {
                    await med.save(doseMg: d, note: 'Dose changed');
                    await HomeWidgetBridge.update();
                  },
                ),
            ],
          ),
          if (med.product.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            SoftCard(
              color: Palette.sky.withValues(alpha: .14),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Text('ℹ️', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(med.product.note,
                        style: const TextStyle(fontSize: 12.5, height: 1.35)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const _MedHistory(),
        ],
      ),
    );
  }
}

/// Spells out what a product change means before it happens.
Future<bool> confirmProductSwitch(
    BuildContext context, GlpProduct from, GlpProduct to) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Change to ${to.brand}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(switchRiskText(from, to),
                style: const TextStyle(fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 12),
            Text(
              'Your dose will be set to the lowest step for ${to.brand} '
              '(${fmtDose(to.doses.first)} mg). Change it only to what you '
              'have actually been prescribed.',
              style: const TextStyle(
                  fontSize: 13, height: 1.45, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nothing is deleted. Every shot, meal and check-in stays, and '
              'each past dose keeps the product it was taken from.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            const Text('Talk to your prescriber before switching.',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Palette.berry)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
              backgroundColor: Palette.berry, minimumSize: const Size(0, 44)),
          child: const Text('I understand'),
        ),
      ],
    ),
  );
  return ok == true;
}

class _MedHistory extends StatelessWidget {
  const _MedHistory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<MedChange>>(
      future: AppDb.instance.medChanges(),
      builder: (context, snap) {
        final items = snap.data ?? const <MedChange>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle('History',
                emoji: '📖',
                trailing: Text('never reset',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant))),
            for (final c in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Text(GlpProduct.byId(c.toProduct).emoji,
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.isFirst
                                ? 'Started ${GlpProduct.byId(c.toProduct).brand} at ${fmtDose(c.toDose)} mg'
                                : c.isProductSwitch
                                    ? '${GlpProduct.byId(c.fromProduct).brand} to ${GlpProduct.byId(c.toProduct).brand} at ${fmtDose(c.toDose)} mg'
                                    : '${fmtDose(c.fromDose ?? 0)} mg to ${fmtDose(c.toDose)} mg',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Text(DateFormat('EEE, MMM d, y').format(c.changedAt),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- reminders

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key, this.showChime = false});
  final bool showChime;

  @override
  Widget build(BuildContext context) => ReminderSettings(showChime: showChime);
}

// ------------------------------------------------------------------- widget

class WidgetPage extends StatelessWidget {
  const WidgetPage({super.key});

  /// Applies a choice and says so. Re-picking what is already selected still
  /// pushes a refresh, so a tap always does something visible.
  Future<void> _apply(BuildContext context,
      {String? style, String? textSize}) async {
    await WidgetPrefs.set(style: style, textSize: textSize);
    await HomeWidgetBridge.update();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(style != null
          ? 'Widget set to ${style == 'simple' ? 'Simple' : 'Detailed'}.'
          : 'Widget text set to ${WidgetPrefs.labelFor(textSize!)}.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: WidgetPrefs.revision,
      builder: (context, _, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Intro(
              'Long-press the widget on your home screen to resize it; it '
              'rearranges to fit.'),
          Row(
            children: [
              Expanded(
                child: _ChoiceTile(
                  emoji: '◎',
                  label: 'Simple',
                  sub: 'Two big rings and your next dose',
                  selected: WidgetPrefs.style == 'simple',
                  onTap: () => _apply(context, style: 'simple'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChoiceTile(
                  emoji: '☰',
                  label: 'Detailed',
                  sub: 'Adds growth, weight and meals',
                  selected: WidgetPrefs.style == 'detailed',
                  onTap: () => _apply(context, style: 'detailed'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionTitle('Text size', emoji: '🔎'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in WidgetPrefs.textSizes)
                Pill(
                  label: WidgetPrefs.labelFor(t),
                  color: Palette.sky,
                  selected: WidgetPrefs.textSize == t,
                  onTap: () => _apply(context, textSize: t),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
              "The app itself follows your phone's font size, so raising that "
              'enlarges every screen here too.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- appearance

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    const modes = [
      (ThemeMode.system, '📱', 'Follow the phone'),
      (ThemeMode.light, '☀️', 'Light'),
      (ThemeMode.dark, '🌙', 'Dark'),
    ];
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Intro('Changes apply right away.'),
          for (final m in modes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChoiceTile(
                emoji: m.$2,
                label: m.$3,
                selected: mode == m.$1,
                wide: true,
                onTap: () => ThemePrefs.set(m.$1),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- backup

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) => const BackupSection();
}

// ----------------------------------------------------------------- advanced

class AdvancedPage extends StatefulWidget {
  const AdvancedPage({super.key});
  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<AdvancedPage> {
  final _key = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(AiService.getKey().then((k) {
      if (k != null && mounted) _key.text = k;
    }).catchError((_) {}));
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Intro(
            'The assistant needs a Gemini API key, free from Google AI Studio.'),
        TextField(
          controller: _key,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Gemini API key',
            helperText: 'Stored in the device keychain',
            prefixIcon: Icon(Icons.key_rounded),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () async {
            if (_key.text.trim().isEmpty) return;
            await AiService.setKey(_key.text);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('API key saved.')));
          },
          icon: const Icon(Icons.check_rounded),
          label: const Text('Save key'),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Setup', emoji: '✨'),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OnboardingScreen(
                onDone: () => Navigator.of(context).pop(),
              ),
            ));
            await Reminders.sync();
            await HomeWidgetBridge.update();
          },
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Run setup again'),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Sounds', emoji: '🔔'),
        OutlinedButton.icon(
          onPressed: Reminders.playChime,
          icon: const Icon(Icons.play_circle_outline_rounded),
          label: const Text('Play the reminder chime'),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- shared bits

/// Selectable tile used by the companion, widget and appearance pages.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.wide = false,
  });

  final String emoji;
  final String label;
  final String? sub;
  final bool selected;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = wide
        ? Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: selected ? scheme.primary : scheme.onSurface)),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: scheme.primary),
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: selected ? scheme.primary : scheme.onSurface)),
              if (sub != null) ...[
                const SizedBox(height: 4),
                Text(sub!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        color: scheme.onSurfaceVariant)),
              ],
            ],
          );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
            vertical: wide ? 16 : 16, horizontal: wide ? 16 : 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: .14)
              : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: selected ? scheme.primary : Colors.transparent, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 14,
                offset: const Offset(0, 6)),
          ],
        ),
        child: body,
      ),
    );
  }
}
