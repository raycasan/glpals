import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ai_service.dart';
import '../db.dart';
import '../med.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widget_bridge.dart';
import '../widgets/common.dart';
import '../widgets/pal_evolution.dart';
import '../widgets/pet.dart';

/// First-launch setup: pick a companion, say what you are taking, and get a
/// starting plan. Everything here is editable later in Settings.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _step = 0;
  bool _saving = false;

  // Step 1
  PetSpecies _pal = PetSpecies.all.first;

  // Step 2
  GlpProduct _product = GlpProduct.all.first;
  late double _dose = _product.doses.first;

  // Step 3
  DateTime? _lastDose;
  int _shotWeekday = DateTime.saturday;
  int _shotMinutes = 9 * 60;

  // Step 4
  final _weight = TextEditingController();
  final _goalWeight = TextEditingController();
  final _height = TextEditingController();

  // Step 5
  final _key = TextEditingController();
  bool _planning = false;
  String? _planError;
  Map<String, dynamic>? _plan;
  late var _goals = Goals.suggestFor(null);

  static const _steps = 5;

  @override
  void dispose() {
    _page.dispose();
    _weight.dispose();
    _goalWeight.dispose();
    _height.dispose();
    _key.dispose();
    super.dispose();
  }

  double? get _weightKg => double.tryParse(_weight.text.trim());

  void _go(int step) {
    if (step < 0 || step >= _steps) return;
    setState(() => _step = step);
    _page.animateToPage(step,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  void _next() {
    if (_step == 3) _recomputeGoals();
    if (_step == _steps - 1) {
      _finish();
    } else {
      _go(_step + 1);
    }
  }

  void _recomputeGoals() {
    final s = Goals.suggestFor(_weightKg);
    setState(() => _goals = s);
  }

  /// Asks Gemini for targets and first-weeks tips based on what was entered.
  Future<void> _buildPlan() async {
    setState(() {
      _planning = true;
      _planError = null;
    });
    try {
      if (_key.text.trim().isNotEmpty) {
        await AiService.setKey(_key.text.trim());
      }
      final r = await AiService.onboardingPlan(
        product: _product.brand,
        molecule: _product.molecule,
        schedule: _product.schedule.label,
        doseMg: _dose,
        weightKg: _weightKg,
        goalWeightKg: double.tryParse(_goalWeight.text.trim()),
        heightCm: double.tryParse(_height.text.trim()),
        startedOn: _lastDose == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_lastDose!),
      );
      setState(() {
        _plan = r;
        _goals = (
          protein: (r['protein_g'] as num?)?.toInt() ?? _goals.protein,
          water: (r['water_ml'] as num?)?.toInt() ?? _goals.water,
          fiber: (r['fiber_g'] as num?)?.toInt() ?? _goals.fiber,
        );
      });
    } catch (e) {
      setState(() => _planError = AiException.from(e).message);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final db = AppDb.instance;
    await PetPrefs.set(_pal);
    await MedPrefs.instance.save(
      product: _product,
      doseMg: _dose,
      startedOn: _lastDose ?? DateTime.now(),
    );
    await Goals.set(
        protein: _goals.protein, water: _goals.water, fiber: _goals.fiber);
    for (final e in {
      'profile_weight_kg': _weight.text.trim(),
      'profile_goal_weight_kg': _goalWeight.text.trim(),
      'profile_height_cm': _height.text.trim(),
    }.entries) {
      if (e.value.isNotEmpty) await db.setSetting(e.key, e.value);
    }

    // A first dose entered here seeds the countdown and the forecast.
    if (_lastDose != null) {
      await db.insertShot(Shot(
        takenAt: _lastDose!,
        doseMg: _dose,
        site: injectionSites.first,
        note: 'Added during setup',
      ));
    }

    final p = ReminderPrefs.instance;
    p.shotWeekday = _shotWeekday;
    p.shotMinutes = _shotMinutes;
    await p.save();

    await db.setSetting('onboarded', 'true');
    HomeWidgetBridge.update();
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  if (_step > 0)
                    IconButton(
                      onPressed: () => _go(_step - 1),
                      icon: const Icon(Icons.arrow_back_rounded),
                      visualDensity: VisualDensity.compact,
                    ),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _steps; i++)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i <= _step
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.primary
                                          .withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _palStep(),
                  _medStep(),
                  _scheduleStep(),
                  _aboutStep(),
                  _planStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: FilledButton.icon(
                onPressed: _saving || _planning ? null : _next,
                icon: Icon(_step == _steps - 1
                    ? Icons.check_rounded
                    : Icons.arrow_forward_rounded),
                label: Text(switch (_step) {
                  0 => "Let's go with ${_pal.name}",
                  1 => 'Continue with ${_product.brand}',
                  4 => 'Start tracking',
                  _ => 'Continue',
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrap(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: children,
      );

  Widget _title(String text, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(sub,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4)),
          const SizedBox(height: 18),
        ],
      );

  // ---- Step 1: companion ----
  Widget _palStep() {
    final theme = Theme.of(context);
    return _wrap([
      _title('Welcome to GLPals 👋',
          'Pick a pal to grow with you. It levels up as you log, and you can swap it any time.'),
      SoftCard(
        gradient: Palette.sunset,
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            PetAvatar(species: _pal, xp: 0, size: 140),
            const SizedBox(height: 10),
            Text(_pal.stages.first.name,
                style:
                    theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(
                'Grows into ${_pal.stages.last.name} ${_pal.stages.last.emoji}',
                style: TextStyle(color: Colors.white.withValues(alpha: .95))),
            const SizedBox(height: 12),
            Theme(
              data: theme.copyWith(
                colorScheme: theme.colorScheme.copyWith(
                  primary: Colors.white,
                  onSurface: Colors.white,
                  onSurfaceVariant: Colors.white70,
                ),
              ),
              child: PalEvolution(species: _pal, xp: 0),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const SectionTitle('Choose your pal', emoji: '🐾'),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .95,
        children: [
          for (final s in PetSpecies.all)
            _PickTile(
              emoji: s.icon,
              label: s.name,
              selected: s.id == _pal.id,
              onTap: () => setState(() => _pal = s),
            ),
        ],
      ),
    ]);
  }

  // ---- Step 2: product and dose ----
  Widget _medStep() {
    final scheme = Theme.of(context).colorScheme;
    return _wrap([
      _title('What are you taking? 💊',
          'This sets your schedule, the countdown and the reminders. Dose steps are the usual ones printed on the pen; your prescriber decides which you are on.'),
      for (final p in GlpProduct.all)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: p.id == _product.id
                ? scheme.primary.withValues(alpha: .14)
                : null,
            onTap: () => setState(() {
              _product = p;
              _dose = p.doses.first;
            }),
            child: Row(
              children: [
                Text(p.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.brand,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: p.id == _product.id
                                  ? scheme.primary
                                  : scheme.onSurface)),
                      Text(p.subtitle,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (p.id == _product.id)
                  Icon(Icons.check_circle_rounded, color: scheme.primary),
              ],
            ),
          ),
        ),
      const SizedBox(height: 14),
      const SectionTitle('Your current dose', emoji: '⚖️'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final d in _product.doses)
            Pill(
              label: '${fmtDose(d)} mg',
              color: Palette.coral,
              selected: d == _dose,
              onTap: () => setState(() => _dose = d),
            ),
        ],
      ),
      if (_product.note.isNotEmpty) ...[
        const SizedBox(height: 14),
        SoftCard(
          color: Palette.sky.withValues(alpha: .14),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Text('ℹ️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_product.note,
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
            ],
          ),
        ),
      ],
    ]);
  }

  // ---- Step 3: schedule ----
  Widget _scheduleStep() {
    final scheme = Theme.of(context).colorScheme;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekly = _product.isWeekly;
    return _wrap([
      _title(
          'When is your dose? 🗓️',
          weekly
              ? 'Your last dose anchors the countdown. If you have not started yet, skip it and pick the day you plan to.'
              : 'A daily product. Pick the time you usually take it.'),
      SoftCard(
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: _lastDose ?? now,
            firstDate: DateTime(now.year - 2),
            lastDate: now,
            helpText: 'When was your last dose?',
          );
          if (d == null || !mounted) return;
          final t = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(_lastDose ?? now),
          );
          if (!mounted) return;
          setState(() => _lastDose =
              DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
        },
        child: Row(
          children: [
            const Text('💉', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      _lastDose == null
                          ? 'Not started yet'
                          : DateFormat('EEE, MMM d · h:mm a')
                              .format(_lastDose!),
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                      _lastDose == null
                          ? 'Tap to add your last dose (optional)'
                          : 'Your last dose. Tap to change.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (_lastDose != null)
              IconButton(
                onPressed: () => setState(() => _lastDose = null),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Clear',
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (weekly) ...[
        const SectionTitle('Preferred day', emoji: '📆'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < 7; i++)
              Pill(
                label: days[i],
                color: Palette.coral,
                selected: _shotWeekday == i + 1,
                onTap: () => setState(() => _shotWeekday = i + 1),
              ),
          ],
        ),
        const SizedBox(height: 18),
      ],
      const SectionTitle('Reminder time', emoji: '⏰'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in [7 * 60, 9 * 60, 12 * 60, 18 * 60, 21 * 60])
            Pill(
              label: ReminderPrefs.fmt(m),
              color: Palette.lavender,
              selected: _shotMinutes == m,
              onTap: () => setState(() => _shotMinutes = m),
            ),
          Pill(
            label: 'Other…',
            emoji: '🕒',
            color: Palette.sky,
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                    hour: _shotMinutes ~/ 60, minute: _shotMinutes % 60),
              );
              if (t != null) {
                setState(() => _shotMinutes = t.hour * 60 + t.minute);
              }
            },
          ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        'You will get a heads-up an hour before, and a nudge to take the pen '
        'out of the fridge so it warms up first.',
        style: TextStyle(
            fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
      ),
    ]);
  }

  // ---- Step 4: about you ----
  Widget _aboutStep() {
    final scheme = Theme.of(context).colorScheme;
    return _wrap([
      _title('A little about you 📏',
          'Used to size your daily protein and fluid targets. All optional, and nothing leaves your phone unless you ask for an AI plan.'),
      TextField(
        controller: _weight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => _recomputeGoals(),
        decoration: const InputDecoration(
            labelText: 'Current weight',
            suffixText: 'kg',
            prefixIcon: Icon(Icons.monitor_weight_outlined)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _goalWeight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
            labelText: 'Goal weight (optional)',
            suffixText: 'kg',
            prefixIcon: Icon(Icons.flag_outlined)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _height,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
            labelText: 'Height (optional)',
            suffixText: 'cm',
            prefixIcon: Icon(Icons.height_rounded)),
      ),
      const SizedBox(height: 16),
      SoftCard(
        color: Palette.mint.withValues(alpha: .14),
        child: Row(
          children: [
            const Text('🥩', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _weightKg == null
                    ? 'Add a weight and I will size your targets to it.'
                    : 'Starting targets: ${_goals.protein} g protein and '
                        '${_goals.water} ml of fluid a day.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.35, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  // ---- Step 5: plan ----
  Widget _planStep() {
    final scheme = Theme.of(context).colorScheme;
    final tips = (_plan?['tips'] as List?)?.cast<String>() ?? const [];
    return _wrap([
      _title('Your starting plan ✨',
          'These are your daily targets. Have them written for your medication by the assistant, or keep the calculated ones.'),
      SoftCard(
        child: Column(
          children: [
            _GoalRow(
              emoji: '🥩',
              label: 'Protein',
              value: '${_goals.protein} g',
              color: Palette.mint,
              onMinus: () => setState(() => _goals = (
                    protein: _goals.protein - 5,
                    water: _goals.water,
                    fiber: _goals.fiber
                  )),
              onPlus: () => setState(() => _goals = (
                    protein: _goals.protein + 5,
                    water: _goals.water,
                    fiber: _goals.fiber
                  )),
            ),
            const Divider(height: 18),
            _GoalRow(
              emoji: '💧',
              label: 'Water',
              value: '${_goals.water} ml',
              color: Palette.sky,
              onMinus: () => setState(() => _goals = (
                    protein: _goals.protein,
                    water: _goals.water - 250,
                    fiber: _goals.fiber
                  )),
              onPlus: () => setState(() => _goals = (
                    protein: _goals.protein,
                    water: _goals.water + 250,
                    fiber: _goals.fiber
                  )),
            ),
            const Divider(height: 18),
            _GoalRow(
              emoji: '🌾',
              label: 'Fiber',
              value: '${_goals.fiber} g',
              color: Palette.peach,
              onMinus: () => setState(() => _goals = (
                    protein: _goals.protein,
                    water: _goals.water,
                    fiber: _goals.fiber - 1
                  )),
              onPlus: () => setState(() => _goals = (
                    protein: _goals.protein,
                    water: _goals.water,
                    fiber: _goals.fiber + 1
                  )),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_plan == null) ...[
        TextField(
          controller: _key,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Gemini API key (optional)',
            helperText: 'Stored in the device keychain. Leave blank to skip.',
            prefixIcon: Icon(Icons.key_rounded),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _planning ? null : _buildPlan,
          icon: _planning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_rounded),
          label: Text(_planning ? 'Writing your plan…' : 'Personalize with AI'),
        ),
      ],
      if (_planError != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_planError!,
              style: const TextStyle(
                  color: Palette.berry,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600)),
        ),
      if (_plan != null) ...[
        SoftCard(
          color: Palette.lavender.withValues(alpha: .14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_plan!['welcome']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14, height: 1.35)),
              const SizedBox(height: 12),
              for (final t in tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                        child: Text(t,
                            style:
                                const TextStyle(fontSize: 12.5, height: 1.4)),
                      ),
                    ],
                  ),
                ),
              if ('${_plan!['watch_for']}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('⚠️ ${_plan!['watch_for']}',
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: Palette.berry)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _planning ? null : _buildPlan,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Write it again'),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        'GLPals is a tracker, not medical advice. Dose changes are always your '
        'prescriber’s call.',
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      ),
    ]);
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
    required this.onMinus,
    required this.onPlus,
  });
  final String emoji;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 17, color: color)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: onMinus,
          icon: const Icon(Icons.remove_rounded, size: 18),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 6),
        IconButton.filled(
          onPressed: onPlus,
          icon: const Icon(Icons.add_rounded, size: 18),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(backgroundColor: color),
        ),
        const SizedBox(width: 2),
        Icon(Icons.tune_rounded, size: 14, color: scheme.onSurfaceVariant),
      ],
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: .16)
              : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 14,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.15 : 1,
              duration: const Duration(milliseconds: 200),
              child: Text(emoji, style: const TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? scheme.primary : scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}
