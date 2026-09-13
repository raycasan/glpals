import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'calendar_screen.dart';
import 'meal_editor.dart';

class FoodScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const FoodScreen({super.key, this.onSaved});
  @override
  State<FoodScreen> createState() => FoodScreenState();
}

class FoodScreenState extends State<FoodScreen> {
  List<Meal> _meals = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final m = await AppDb.instance.meals(limit: 60);
    if (mounted) setState(() => _meals = m);
  }

  Future<void> _afterChange() async {
    await refresh();
    widget.onSaved?.call();
  }

  Future<void> _add() async {
    if (await openMealEditor(context)) await _afterChange();
  }

  Future<void> _edit(Meal m) async {
    if (await openMealEditor(context, existing: m)) await _afterChange();
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CalendarScreen(onChanged: widget.onSaved),
    ));
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayMeals = _meals
        .where((m) => m.eatenAt.toIso8601String().startsWith(today))
        .toList();
    final protein = todayMeals.fold<int>(0, (a, m) => a + m.proteinG);
    final fiber = todayMeals.fold<int>(0, (a, m) => a + m.fiberG);
    final calories = todayMeals.fold<int>(0, (a, m) => a + m.calories);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'meal_fab',
        onPressed: _add,
        icon: const Icon(Icons.camera_alt_rounded),
        label: const Text('Log meal'),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            SoftCard(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RingStat(
                      value: protein,
                      goal: Goals.proteinG,
                      unit: 'g',
                      label: 'Protein',
                      color: Palette.mint,
                      emoji: '🥩'),
                  _RingStat(
                      value: fiber,
                      goal: Goals.fiberG,
                      unit: 'g',
                      label: 'Fiber',
                      color: Palette.peach,
                      emoji: '🌾'),
                  _RingStat(
                      value: calories,
                      goal: Goals.caloriesKcal,
                      unit: 'kcal',
                      label: 'Energy',
                      color: Palette.coral,
                      emoji: '🔥'),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Palette.lavender.withValues(alpha: .15)),
                          alignment: Alignment.center,
                          child: Text('${todayMeals.length}',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Palette.lavender)),
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(height: 19),
                        Text('meal${todayMeals.length == 1 ? '' : 's'}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SoftCard(
              onTap: _openCalendar,
              color: Palette.lavender.withValues(alpha: .14),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Text('🗓️', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Calendar', style: theme.textTheme.titleMedium),
                        Text('Look back at any day and fill in what you missed',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_meals.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState(
                  emoji: '📸',
                  title: 'No meals yet',
                  body:
                      'Snap a photo of your plate or type what you ate. I will estimate protein, fiber and calories.',
                ),
              )
            else
              SectionTitle('Recent meals',
                  emoji: '🍽️',
                  trailing: Text('tap to edit',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant))),
            for (final m in _meals)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Dismissible(
                  key: ValueKey(m.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => confirmDelete(
                    context,
                    title: 'Delete this meal?',
                    body:
                        '"${m.description}" will be removed from your day totals.',
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                        color: Palette.berry,
                        borderRadius: BorderRadius.circular(24)),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 22),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await AppDb.instance.deleteMeal(m.id!);
                    await _afterChange();
                  },
                  child: MealTile(meal: m, onTap: () => _edit(m)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RingStat extends StatelessWidget {
  const _RingStat({
    required this.value,
    required this.goal,
    required this.unit,
    required this.label,
    required this.color,
    required this.emoji,
  });
  final int value;
  final int goal;
  final String unit;
  final String label;
  final Color color;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tracked = goal <= 0;
    return Expanded(
      child: Column(
        children: [
          GoalRing(
            progress: tracked ? 0 : value / goal,
            color: color,
            size: 60,
            child: Text(!tracked && value >= goal ? '✅' : emoji,
                style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Text('$value',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          Text(tracked ? '$label · $unit' : '$label · of $goal',
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
