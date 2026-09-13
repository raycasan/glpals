import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../med.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'checkin_screen.dart';
import 'meal_editor.dart';

/// Month calendar for looking back at any day: what was eaten, whether a
/// check-in was saved and whether a shot was taken. Tapping a day opens that
/// day's meals, which can be edited, deleted or added to.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.onChanged, this.initialDay});

  /// Called after anything is saved, so Home and the widget can refresh.
  final VoidCallback? onChanged;
  final DateTime? initialDay;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month; // first day of the visible month
  late DateTime _selected; // selected day, time stripped

  Map<String, List<Meal>> _meals = {};
  Map<String, DailyLog> _logs = {};
  Map<String, List<Shot>> _shots = {};

  /// Days a dose is projected to fall on, shown as a hollow marker.
  Map<String, ForecastDose> _forecast = {};
  bool _loading = true;

  final _scroll = ScrollController();
  final _detailKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final start = dateOnly(widget.initialDay ?? DateTime.now());
    _selected = start;
    _month = DateTime(start.year, start.month);
    _load();
  }

  /// The grid always shows whole weeks, so it reaches into the neighbouring
  /// months; data is loaded for that same visible range.
  DateTime get _gridStart {
    final first = DateTime(_month.year, _month.month);
    return first.subtract(Duration(days: first.weekday % 7)); // week starts Sun
  }

  DateTime get _gridEnd => _gridStart.add(const Duration(days: 41));

  Future<void> _load() async {
    final db = AppDb.instance;
    final from = dayKey(_gridStart);
    final to = dayKey(_gridEnd);
    final meals = await db.mealsBetween(from, to);
    final logs = await db.logsBetween(from, to);
    final shots = await db.shotsBetween(from, to);
    if (!mounted) return;
    final byDay = <String, List<Meal>>{};
    for (final m in meals) {
      byDay.putIfAbsent(dayKey(m.eatenAt), () => []).add(m);
    }
    final shotsByDay = <String, List<Shot>>{};
    for (final s in shots) {
      shotsByDay.putIfAbsent(dayKey(s.takenAt), () => []).add(s);
    }
    // Project far enough ahead to cover any month the grid can show.
    final last = await db.lastShot();
    final lastSkip = await db.lastSkip();
    final upcoming = forecastDoses(
      last: last,
      intervalDays: MedPrefs.instance.intervalDays,
      count: MedPrefs.instance.intervalDays == 1 ? 400 : 60,
      atMinutes: ReminderPrefs.instance.shotMinutes,
      lastSkipPlannedFor: lastSkip?.plannedFor,
    );
    setState(() {
      _meals = byDay;
      _logs = {for (final l in logs) l.day: l};
      _shots = shotsByDay;
      _forecast = {
        for (final f in upcoming)
          if (!shotsByDay.containsKey(dayKey(f.due))) dayKey(f.due): f
      };
      _loading = false;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the selected day's card into view after a tap on the grid, so the
  /// meals for that day are right there instead of a scroll away.
  void _scrollToDetail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _detailKey.currentContext;
      if (ctx == null || !_scroll.hasClients) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0,
      );
    });
  }

  void _scrollToCalendar() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _loading = true;
    });
    _load();
  }

  void _jumpToToday() {
    final now = dateOnly(DateTime.now());
    setState(() {
      _selected = now;
      _month = DateTime(now.year, now.month);
      _loading = true;
    });
    _load();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Jump to a day',
    );
    if (picked == null) return;
    setState(() {
      _selected = dateOnly(picked);
      _month = DateTime(picked.year, picked.month);
      _loading = true;
    });
    _load();
  }

  Future<void> _afterChange() async {
    widget.onChanged?.call();
    await _load();
  }

  Future<void> _addMeal() async {
    if (await openMealEditor(context, initialDate: _selected)) {
      await _afterChange();
    }
  }

  Future<void> _editMeal(Meal m) async {
    if (await openMealEditor(context, existing: m)) await _afterChange();
  }

  /// Adds or removes a glass of water on the selected day, creating that day's
  /// log if it does not exist yet. Backfilling water should not need a trip
  /// through the check-in screen.
  Future<void> _adjustWater(int deltaMl) async {
    final key = dayKey(_selected);
    final log = _logs[key];
    final next = ((log?.waterMl ?? 0) + deltaMl).clamp(0, 20000);
    await AppDb.instance.upsertLog(DailyLog(
      day: key,
      weightKg: log?.weightKg,
      waterMl: next,
      proteinG: log?.proteinG ?? 0,
      sideEffects: log?.sideEffects,
      note: log?.note ?? '',
    ));
    await _afterChange();
  }

  Future<void> _editCheckIn() async {
    final key = dayKey(_selected);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
            title: Text(DateFormat('EEE, MMM d').format(_selected)),
            actions: const [
              Padding(
                  padding: EdgeInsets.only(right: 16),
                  child:
                      Center(child: Text('📝', style: TextStyle(fontSize: 22))))
            ]),
        body: CheckInScreen(day: key, onSaved: widget.onChanged),
      ),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar 🗓️'),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_rounded),
            tooltip: 'Jump to a day',
            onPressed: _pickMonth,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child:
                TextButton(onPressed: _jumpToToday, child: const Text('Today')),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'calendar_meal_fab',
        onPressed: _addMeal,
        icon: const Icon(Icons.add_rounded),
        label: Text(_selected == today ? 'Log meal' : 'Add to this day'),
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          SoftCard(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    _ArrowBtn(Icons.chevron_left_rounded, () => _shiftMonth(-1),
                        'Previous month'),
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickMonth,
                        child: Center(
                          child: Text(DateFormat('MMMM y').format(_month),
                              style: theme.textTheme.titleLarge),
                        ),
                      ),
                    ),
                    _ArrowBtn(Icons.chevron_right_rounded, () => _shiftMonth(1),
                        'Next month'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final d in const [
                      'Sun',
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat'
                    ])
                      Expanded(
                        child: Center(
                          child: Text(d,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurfaceVariant)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -120) _shiftMonth(1);
                    if (v > 120) _shiftMonth(-1);
                  },
                  child: GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: .78,
                    children: [
                      for (var i = 0; i < 42; i++) _cell(i, today),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const _Legend(),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _MonthSummary(
            month: _month,
            meals: _meals,
            logs: _logs,
            shots: _shots,
          ),
          const SizedBox(height: 18),
          SectionTitle(
            key: _detailKey,
            _selected == today
                ? 'Today'
                : DateFormat('EEEE, MMM d').format(_selected),
            emoji: '🍽️',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _scrollToCalendar,
                  icon: const Icon(Icons.calendar_month_rounded, size: 20),
                  tooltip: 'Back to the calendar',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: Palette.lavender.withValues(alpha: .16),
                    foregroundColor: Palette.lavender,
                  ),
                ),
                TextButton.icon(
                  onPressed: _editCheckIn,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Check-in'),
                ),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _DaySummary(
              log: _logs[dayKey(_selected)],
              meals: _meals[dayKey(_selected)] ?? const [],
              shots: _shots[dayKey(_selected)] ?? const [],
              onWater: _adjustWater,
              forecast: _forecast[dayKey(_selected)],
            ),
            const SizedBox(height: 14),
            ..._dayMeals(),
          ],
        ],
      ),
    );
  }

  List<Widget> _dayMeals() {
    final meals = _meals[dayKey(_selected)] ?? const <Meal>[];
    if (meals.isEmpty) {
      return [
        SoftCard(
          onTap: _addMeal,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
          child: Row(
            children: [
              const Text('🍽️', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No meals on this day',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('Tap to add one, even long after the fact.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.add_rounded),
            ],
          ),
        ),
      ];
    }
    return [
      for (final m in meals)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey('meal_${m.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => confirmDelete(
              context,
              title: 'Delete this meal?',
              body: '"${m.description}" will be removed from your day totals.',
            ),
            background: Container(
              decoration: BoxDecoration(
                  color: Palette.berry,
                  borderRadius: BorderRadius.circular(24)),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              child:
                  const Icon(Icons.delete_outline_rounded, color: Colors.white),
            ),
            onDismissed: (_) async {
              await AppDb.instance.deleteMeal(m.id!);
              await _afterChange();
            },
            child: MealTile(meal: m, onTap: () => _editMeal(m)),
          ),
        ),
    ];
  }

  Widget _cell(int index, DateTime today) {
    final date = _gridStart.add(Duration(days: index));
    final key = dayKey(date);
    final meals = _meals[key] ?? const <Meal>[];
    final protein = meals.fold<int>(0, (a, m) => a + m.proteinG);
    return _DayCell(
      date: date,
      inMonth: date.month == _month.month,
      isToday: date == today,
      isFuture: date.isAfter(today),
      selected: date == _selected,
      mealCount: meals.length,
      proteinProgress: protein / Goals.proteinG,
      hasLog: _logs.containsKey(key),
      hasShot: _shots.containsKey(key),
      dueShot: _forecast.containsKey(key),
      onTap: () {
        setState(() => _selected = date);
        _scrollToDetail();
      },
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn(this.icon, this.onTap, this.tooltip);
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: scheme.primary.withValues(alpha: .12),
        foregroundColor: scheme.primary,
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.isFuture,
    required this.selected,
    required this.mealCount,
    required this.proteinProgress,
    required this.hasLog,
    required this.hasShot,
    required this.dueShot,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final bool isToday;
  final bool isFuture;
  final bool selected;
  final int mealCount;
  final double proteinProgress;
  final bool hasLog;
  final bool hasShot;

  /// A projected dose, not one that happened.
  final bool dueShot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faded = !inMonth || isFuture;
    final numberColor = selected
        ? Colors.white
        : faded
            ? scheme.onSurfaceVariant.withValues(alpha: .45)
            : scheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (proteinProgress > 0 && !selected)
                  GoalRing(
                      progress: proteinProgress,
                      color: Palette.mint,
                      size: 38,
                      stroke: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? scheme.primary : Colors.transparent,
                    border: isToday && !selected
                        ? Border.all(color: scheme.primary, width: 2)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text('${date.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday || selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: numberColor,
                      )),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 7,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (mealCount > 0) const _Dot(Palette.sunshine),
                if (hasLog) const _Dot(Palette.lavender),
                if (hasShot) const _Dot(Palette.coral),
                if (dueShot && !hasShot)
                  const _Dot(Palette.coral, hollow: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, {this.hollow = false});
  final Color color;

  /// Hollow marks something predicted rather than logged.
  final bool hollow;
  @override
  Widget build(BuildContext context) => Container(
        width: hollow ? 6 : 5,
        height: hollow ? 6 : 5,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? Colors.transparent : color,
          border: hollow ? Border.all(color: color, width: 1.4) : null,
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(c),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
          ],
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 4,
      children: [
        item(Palette.sunshine, 'meals'),
        item(Palette.lavender, 'check-in'),
        item(Palette.coral, 'shot'),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Dot(Palette.coral, hollow: true),
            const SizedBox(width: 4),
            Text('due',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: GoalRing(
                  progress: .7, color: Palette.mint, size: 12, stroke: 2.5),
            ),
            const SizedBox(width: 5),
            Text('protein',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({
    required this.month,
    required this.meals,
    required this.logs,
    required this.shots,
  });

  final DateTime month;
  final Map<String, List<Meal>> meals;
  final Map<String, DailyLog> logs;
  final Map<String, List<Shot>> shots;

  bool _inMonth(String key) =>
      key.startsWith(DateFormat('yyyy-MM').format(month));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mealDays = meals.keys.where(_inMonth).toList();
    final mealCount =
        mealDays.fold<int>(0, (a, k) => a + (meals[k]?.length ?? 0));
    final proteinTotal = mealDays.fold<int>(
        0, (a, k) => a + (meals[k]!.fold<int>(0, (b, m) => b + m.proteinG)));
    final checkIns = logs.keys.where(_inMonth).length;
    final shotCount = shots.keys
        .where(_inMonth)
        .fold<int>(0, (a, k) => a + (shots[k]?.length ?? 0));
    final avgProtein =
        mealDays.isEmpty ? 0 : (proteinTotal / mealDays.length).round();

    Widget stat(String emoji, String value, String label) => Expanded(
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        );

    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Row(
        children: [
          stat('🍽️', '$mealCount', 'meals'),
          stat('📝', '$checkIns', 'check-ins'),
          stat('💉', '$shotCount', 'shots'),
          stat('🥩', '$avgProtein g', 'avg protein\non meal days'),
        ],
      ),
    );
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({
    required this.log,
    required this.meals,
    required this.shots,
    required this.onWater,
    required this.forecast,
  });
  final DailyLog? log;
  final List<Meal> meals;
  final List<Shot> shots;

  /// Set when a dose is projected for this day.
  final ForecastDose? forecast;

  /// Called with a millilitre delta when the glasses are tapped.
  final ValueChanged<int> onWater;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final protein = meals.fold<int>(0, (a, m) => a + m.proteinG);
    final fiber = meals.fold<int>(0, (a, m) => a + m.fiberG);
    final calories = meals.fold<int>(0, (a, m) => a + m.calories);
    final water = log?.waterMl ?? 0;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(
                  label: '$protein g protein',
                  emoji: '🥩',
                  dense: true,
                  color: Palette.mint),
              Pill(
                  label: '$fiber g fiber',
                  emoji: '🌾',
                  dense: true,
                  color: Palette.peach),
              Pill(
                  label: '~$calories kcal',
                  emoji: '🔥',
                  dense: true,
                  color: Palette.coral),
              if (log?.weightKg != null)
                Pill(
                    label: '${log!.weightKg} kg',
                    emoji: '⚖️',
                    dense: true,
                    color: Palette.lavender),
              for (final s in shots)
                Pill(
                    label: '${fmtDose(s.doseMg)} mg · ${s.site}',
                    emoji: '💉',
                    dense: true,
                    color: siteColor(s.site)),
              if (forecast != null && shots.isEmpty)
                Pill(
                    label: 'Dose due · ${forecast!.site}',
                    emoji: '🔮',
                    dense: true,
                    color: Palette.coral),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('💧', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$water of ${Goals.waterMl} ml',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (water / Goals.waterMl).clamp(0, 1),
                        minHeight: 8,
                        color: Palette.sky,
                        backgroundColor: Palette.sky.withValues(alpha: .16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _WaterBtn(
                  icon: Icons.remove_rounded,
                  onTap: water == 0 ? null : () => onWater(-kGlassMl)),
              const SizedBox(width: 6),
              _WaterBtn(
                  icon: Icons.add_rounded,
                  filled: true,
                  onTap: () => onWater(kGlassMl)),
            ],
          ),
          if (log != null && log!.sideEffectTotal > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in log!.sideEffects.entries)
                  if (e.value > 0)
                    Text(
                        '${sideEffectEmoji[e.key] ?? '•'} ${e.key.replaceAll('_', ' ')} · ${severityLabels[e.value]}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: severityColors[e.value])),
              ],
            ),
          ],
          if ((log?.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('“${log!.note}”',
                style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant)),
          ],
          if (log == null &&
              meals.isEmpty &&
              shots.isEmpty &&
              forecast == null) ...[
            const SizedBox(height: 10),
            Text('Nothing logged on this day yet.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// One meal row, shared by the calendar and the meals list.
class MealTile extends StatelessWidget {
  const MealTile({super.key, required this.meal, required this.onTap});
  final Meal meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final has = meal.photoPath != null && File(meal.photoPath!).existsSync();
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: has
                ? Image.file(File(meal.photoPath!),
                    width: 64, height: 64, fit: BoxFit.cover)
                : Container(
                    width: 64,
                    height: 64,
                    color: Palette.sunshine.withValues(alpha: .25),
                    alignment: Alignment.center,
                    child: const Text('🍽️', style: TextStyle(fontSize: 26)),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                Text(
                    '${relativeDay(meal.eatenAt)} · ${DateFormat('h:mm a').format(meal.eatenAt)}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(
                        label: '${meal.proteinG} g',
                        emoji: '🥩',
                        dense: true,
                        color: Palette.mint),
                    Pill(
                        label: '${meal.fiberG} g',
                        emoji: '🌾',
                        dense: true,
                        color: Palette.peach),
                    Pill(
                        label: '~${meal.calories} kcal',
                        emoji: '🔥',
                        dense: true,
                        color: Palette.coral),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small round +/- used by the day's water row.
class _WaterBtn extends StatelessWidget {
  const _WaterBtn({required this.icon, this.onTap, this.filled = false});
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: !enabled
          ? scheme.onSurface.withValues(alpha: .06)
          : filled
              ? Palette.sky
              : Palette.sky.withValues(alpha: .16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon,
              size: 20,
              color: !enabled
                  ? scheme.onSurfaceVariant
                  : filled
                      ? Colors.white
                      : Palette.sky),
        ),
      ),
    );
  }
}
