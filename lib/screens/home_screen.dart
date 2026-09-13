import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../med.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dose_alert.dart';
import '../widgets/pal_art.dart';
import '../widgets/pet.dart';
import '../xp.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onLogShot;
  final VoidCallback onCheckIn;
  final VoidCallback onLogMeal;
  final VoidCallback onAsk;
  const HomeScreen({
    super.key,
    required this.onLogShot,
    required this.onCheckIn,
    required this.onLogMeal,
    required this.onAsk,
  });
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _streak = 0;
  Shot? _last;
  String _nextSite = injectionSites.first;
  DailyLog? _today;
  int _mealProtein = 0;
  int _mealFiber = 0;
  int _mealCalories = 0;
  DoseSkip? _lastSkip;
  XpSummary _xp = XpSummary.empty;

  /// Keeps the shot countdown honest without a rebuild storm.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    refresh();
    _tick = Timer.periodic(
        const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final db = AppDb.instance;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final s = await db.streak();
    final l = await db.lastShot();
    final n = await db.suggestedSite();
    final t = await db.logFor(today);
    final todayMeals = await db.mealsOn(today);
    final p = todayMeals.fold<int>(0, (a, m) => a + m.proteinG);
    final fiber = todayMeals.fold<int>(0, (a, m) => a + m.fiberG);
    final kcal = todayMeals.fold<int>(0, (a, m) => a + m.calories);
    final skip = await db.lastSkip();
    final xp = await Xp.compute();
    if (mounted) {
      setState(() {
        _streak = s;
        _last = l;
        _nextSite = n;
        _today = t;
        _mealProtein = p;
        _mealFiber = fiber;
        _mealCalories = kcal;
        _lastSkip = skip;
        _xp = xp;
      });
    }
  }

  /// When the next dose is due, from the last logged shot (or a deliberately
  /// skipped one) and the product's schedule.
  DateTime? get _nextDoseAt => nextDoseAt(
        last: _last,
        lastSkipPlannedFor: _lastSkip?.plannedFor,
        intervalDays: MedPrefs.instance.intervalDays,
      );

  /// Records a deliberate skip after explaining what it means.
  Future<void> _skipDose(DateTime due) async {
    final skipped = await confirmSkipDose(context,
        due: due, product: MedPrefs.instance.product);
    if (!skipped) return;
    await refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Dose skipped. Countdown moved to the next one.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final due = _nextDoseAt;
    final left = due?.difference(now);
    final overdue = left != null && left.isNegative;
    final water = _today?.waterMl ?? 0;
    final protein = math.max(_today?.proteinG ?? 0, _mealProtein);
    const white = Colors.white;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Text(greeting(), style: theme.textTheme.headlineSmall),
          Text(DateFormat('EEEE, MMMM d').format(now),
              style: TextStyle(
                  color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),

          // Pet hero
          ValueListenableBuilder<PetSpecies>(
            valueListenable: petSpecies,
            builder: (context, species, _) {
              final stage = species.stageFor(_xp.total);
              final next = species.next(stage);
              final toNext = Xp.toNext(_xp.total);
              return SoftCard(
                gradient: Palette.sunset,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        PetAvatar(
                          species: species,
                          xp: _xp.total,
                          size: 112,
                          mood: PetStage.moodFor(
                              streak: _streak, checkedInToday: _today != null),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(stage.name,
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(color: white)),
                              const SizedBox(height: 4),
                              Text(PetStage.mood(_streak),
                                  style: TextStyle(
                                      color: white.withValues(alpha: .95),
                                      height: 1.3)),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _HeroChip(_streak == 0
                                      ? '🔥 Start a streak today'
                                      : '🔥 $_streak-day streak'),
                                  _HeroChip('⭐ ${_xp.total} XP'),
                                  if (_xp.today.earned > 0)
                                    _HeroChip('+${_xp.today.earned} today'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (next != null) ...[
                      Row(
                        children: [
                          Text('Next:',
                              style: TextStyle(
                                  color: white.withValues(alpha: .95),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 4),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: white.withValues(alpha: .22),
                            ),
                            child: PalArt(
                              species: species.id,
                              stage: species.stages.indexOf(next),
                              size: 30,
                              phase: .25,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(next.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: white.withValues(alpha: .95),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Text(
                            '$toNext XP to go',
                            style: TextStyle(
                                color: white.withValues(alpha: .95),
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: species.progress(_xp.total),
                          minHeight: 10,
                          color: white,
                          backgroundColor: white.withValues(alpha: .25),
                        ),
                      ),
                    ] else
                      const Text('🏆 Max level reached. You are unstoppable!',
                          style: TextStyle(
                              color: white, fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 22),
          SectionTitle('Today', emoji: '📅', trailing: _XpPill(_xp.today)),
          Row(
            children: [
              Expanded(
                child: _GoalTile(
                  emoji: '💧',
                  label: 'Water',
                  value: water,
                  goal: Goals.waterMl,
                  unit: 'ml',
                  color: Palette.sky,
                  onTap: widget.onCheckIn,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GoalTile(
                  emoji: '🥩',
                  label: 'Protein',
                  value: protein,
                  goal: Goals.proteinG,
                  unit: 'g',
                  color: Palette.mint,
                  onTap: widget.onCheckIn,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _GoalTile(
                  emoji: '🔥',
                  label: 'Energy',
                  value: _mealCalories,
                  goal: Goals.caloriesKcal,
                  unit: 'kcal',
                  color: Palette.coral,
                  onTap: widget.onLogMeal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GoalTile(
                  emoji: '🌾',
                  label: 'Fiber',
                  value: _mealFiber,
                  goal: Goals.fiberG,
                  unit: 'g',
                  color: Palette.peach,
                  onTap: widget.onLogMeal,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),
          const SectionTitle('Ways to grow', emoji: '⭐'),
          _QuestCard(
            score: _xp.today,
            onCheckIn: widget.onCheckIn,
            onLogMeal: widget.onLogMeal,
            onLogShot: widget.onLogShot,
          ),

          const SizedBox(height: 22),
          SectionTitle(overdue ? 'Action needed' : 'Next shot',
              emoji: overdue ? '⚠️' : '💉'),
          if (overdue) ...[
            OverdueBanner(
              due: due!,
              product: MedPrefs.instance.product,
              onLog: widget.onLogShot,
              onSkip: () => _skipDose(due),
            ),
            const SizedBox(height: 12),
          ],
          _ShotCard(
            last: _last,
            dueAt: due,
            left: left,
            nextSite: _nextSite,
            onTap: widget.onLogShot,
          ),

          const SizedBox(height: 22),
          const SectionTitle('Quick actions', emoji: '⚡'),
          Row(
            children: [
              Expanded(
                  child: _ActionTile(
                      '💉', 'Log a shot', Palette.coral, widget.onLogShot)),
              const SizedBox(width: 12),
              Expanded(
                  child: _ActionTile("📝", "Today's check-in", Palette.mint,
                      widget.onCheckIn)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _ActionTile(
                      '📸', 'Log a meal', Palette.sunshine, widget.onLogMeal)),
              const SizedBox(width: 12),
              Expanded(
                  child: _ActionTile(
                      '💬', 'Ask your buddy', Palette.lavender, widget.onAsk)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      );
}

class _XpPill extends StatelessWidget {
  const _XpPill(this.score);
  final DayScore score;
  @override
  Widget build(BuildContext context) => Pill(
        label: '${score.earned} XP today',
        emoji: '⭐',
        dense: true,
        color: Palette.sunshine,
      );
}

/// The day's earnable list. Each row says what it is worth and opens the
/// screen where it gets done.
class _QuestCard extends StatelessWidget {
  const _QuestCard({
    required this.score,
    required this.onCheckIn,
    required this.onLogMeal,
    required this.onLogShot,
  });

  final DayScore score;
  final VoidCallback onCheckIn;
  final VoidCallback onLogMeal;
  final VoidCallback onLogShot;

  VoidCallback _target(Quest q) => switch (q.id) {
        'meal' || 'fiber' => onLogMeal,
        'shot' => onLogShot,
        _ => onCheckIn,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quests = [...Quest.daily, Quest.shot];
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: Column(
        children: [
          for (final q in quests)
            InkWell(
              onTap: _target(q),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    _QuestCheck(done: score.has(q), color: q.color),
                    const SizedBox(width: 12),
                    Text(q.emoji, style: const TextStyle(fontSize: 17)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        q.repeatable > 1 && score.count(q) > 0
                            ? '${q.label} (${score.count(q)} of ${q.repeatable})'
                            : q.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: score.has(q)
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      score.has(q)
                          ? '+${score.xpFor(q)}'
                          : '+${q.xp}${q.repeatable > 1 ? ' ea' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: score.has(q) ? q.color : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 2),
            child: Row(
              children: [
                const Text('🌟', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    score.has(Quest.perfect)
                        ? 'Perfect day. Your pal is thrilled.'
                        : 'Check-in, a meal, protein and water in one day',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: score.has(Quest.perfect)
                            ? Palette.berry
                            : scheme.onSurfaceVariant),
                  ),
                ),
                Text('+${Quest.perfect.xp}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: score.has(Quest.perfect)
                          ? Palette.berry
                          : scheme.onSurfaceVariant,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestCheck extends StatelessWidget {
  const _QuestCheck({required this.done, required this.color});
  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? color : Colors.transparent,
        border:
            Border.all(color: done ? color : scheme.outlineVariant, width: 2),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.emoji,
    required this.label,
    required this.value,
    required this.goal,
    required this.unit,
    required this.color,
    required this.onTap,
  });
  final String emoji;
  final String label;
  final int value;
  final int goal;
  final String unit;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tracked = goal <= 0;
    final done = !tracked && value >= goal;
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          GoalRing(
            // No target set: the ring stays a quiet track and the number does
            // the talking.
            progress: tracked ? 0 : value / goal,
            color: color,
            size: 68,
            child:
                Text(done ? '✅' : emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(height: 10),
          Text('$value $unit',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(tracked ? '$label today' : 'of $goal $unit · $label',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ShotCard extends StatelessWidget {
  const _ShotCard({
    required this.last,
    required this.dueAt,
    required this.left,
    required this.nextSite,
    required this.onTap,
  });
  final Shot? last;
  final DateTime? dueAt;
  final Duration? left;
  final String nextSite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final med = MedPrefs.instance.product;
    final overdue = left != null && left!.isNegative;
    final soon = left != null && !overdue && left! <= const Duration(hours: 2);
    final accent = overdue || soon ? Palette.mint : Palette.coral;
    final title = last == null
        ? 'No ${med.injected ? 'shots' : 'doses'} logged yet'
        : overdue
            ? '${med.injected ? 'Shot' : 'Dose'} day is here!'
            : 'In ${fmtCountdown(left!)}';
    final subtitle = last == null
        ? 'Log your first one to start the countdown.'
        : '${med.brand} · ${DateFormat('EEE, MMM d · h:mm a').format(dueAt!)}';

    return SoftCard(
      onTap: onTap,
      color: overdue || soon ? Palette.mint.withValues(alpha: .14) : null,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: .15)),
                alignment: Alignment.center,
                child: left == null
                    ? Text(med.emoji, style: const TextStyle(fontSize: 28))
                    : overdue
                        ? const Text('🎯', style: TextStyle(fontSize: 28))
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_bigNumber(left!),
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: accent,
                                      height: 1)),
                              Text(_bigUnit(left!),
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: accent,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    if (med.injected)
                      Pill(
                          label: 'Next site: $nextSite',
                          emoji: '📍',
                          dense: true,
                          color: siteColor(nextSite)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
          // Pens sit more comfortably at room temperature.
          if (soon && med.needsFridge) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Palette.sky.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Text('🧊', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Take your pen out of the fridge now. About 30 minutes at '
                      'room temperature makes the shot much more comfortable.',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _bigNumber(Duration d) {
    if (d.inDays > 0) return '${d.inDays}';
    if (d.inHours > 0) return '${d.inHours}';
    return '${d.inMinutes}';
  }

  String _bigUnit(Duration d) {
    if (d.inDays > 0) return d.inDays == 1 ? 'day' : 'days';
    if (d.inHours > 0) return d.inHours == 1 ? 'hour' : 'hours';
    return 'min';
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.emoji, this.label, this.color, this.onTap);
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      color: color.withValues(alpha: .16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).cardTheme.color),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(height: 12),
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ],
      ),
    );
  }
}
