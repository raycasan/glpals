import 'package:flutter/material.dart';

import '../reminders.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Reminder controls for the Settings sheet. Every reminder is opt-in.
class ReminderSettings extends StatelessWidget {
  const ReminderSettings({super.key, this.showChime = false});

  /// Shows the chime test tile (hidden by default, see Settings long-press).
  final bool showChime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = ReminderPrefs.instance;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return ListenableBuilder(
      listenable: p,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reminders', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              'All optional. They quiet down on their own once the thing is logged.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),

          // ---- Shot
          _Group(
            emoji: '💉',
            title: 'Shot day',
            subtitle:
                'Follows your last logged shot. The day below is used until your first one.',
            value: p.shotOn,
            onChanged: (v) {
              p.shotOn = v;
              p.save();
            },
            color: Palette.coral,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Pill(
                        label: days[i],
                        dense: true,
                        color: Palette.coral,
                        selected: p.shotWeekday == i + 1,
                        onTap: () {
                          p.shotWeekday = i + 1;
                          p.save();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _TimePill(
                  label: 'Remind at',
                  minutes: p.shotMinutes,
                  color: Palette.coral,
                  onPicked: (m) {
                    p.shotMinutes = m;
                    p.save();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Countdown before the shot
          _Group(
            emoji: '⏳',
            title: 'Before your shot',
            subtitle:
                'A heads-up with its own chime, and a nudge to warm the pen.',
            value: p.countdownOn,
            onChanged: (v) {
              p.countdownOn = v;
              p.save();
            },
            color: Palette.lavender,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Heads-up',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    for (final m in [30, 60, 90, 120])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Pill(
                          label: m >= 60 ? '${m ~/ 60} h' : '$m m',
                          dense: true,
                          color: Palette.lavender,
                          selected: p.countdownMinutes == m,
                          onTap: () {
                            p.countdownMinutes = m;
                            p.save();
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('🧊', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Take the pen out of the fridge',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    Switch(
                      value: p.fridgeOn,
                      onChanged: (v) {
                        p.fridgeOn = v;
                        p.save();
                      },
                    ),
                  ],
                ),
                if (p.fridgeOn)
                  Row(
                    children: [
                      Text('Warm for',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      for (final m in [30, 45, 60])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Pill(
                            label: '$m m',
                            dense: true,
                            color: Palette.sky,
                            selected: p.fridgeMinutes == m,
                            onTap: () {
                              p.fridgeMinutes = m;
                              p.save();
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Water
          _Group(
            emoji: '💧',
            title: 'Drink water',
            subtitle:
                'Nudges through the day, paused for the day once you reach ${Goals.waterMl} ml.',
            value: p.waterOn,
            onChanged: (v) {
              p.waterOn = v;
              p.save();
            },
            color: Palette.sky,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TimePill(
                      label: 'From',
                      minutes: p.waterStart,
                      color: Palette.sky,
                      onPicked: (m) {
                        p.waterStart = m;
                        if (p.waterEnd <= m) {
                          p.waterEnd = (m + 60).clamp(0, 23 * 60 + 59);
                        }
                        p.save();
                      },
                    ),
                    _TimePill(
                      label: 'Until',
                      minutes: p.waterEnd,
                      color: Palette.sky,
                      onPicked: (m) {
                        p.waterEnd = m;
                        if (p.waterStart >= m) {
                          p.waterStart = (m - 60).clamp(0, 23 * 60);
                        }
                        p.save();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Every',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    for (final h in [1, 2, 3])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Pill(
                          label: '$h h',
                          dense: true,
                          color: Palette.sky,
                          selected: p.waterEveryHours == h,
                          onTap: () {
                            p.waterEveryHours = h;
                            p.save();
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Meals
          SoftCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            color: Palette.sunshine.withValues(alpha: .12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🍽️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Log your meals',
                              style: theme.textTheme.titleMedium),
                          Text(
                              'Skipped for the day once a meal is logged around that time.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final slot in MealSlot.all)
                  Row(
                    children: [
                      Text(slot.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(slot.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      if (p.mealOn[slot.id] ?? false)
                        _TimePill(
                          minutes:
                              p.mealMinutes[slot.id] ?? slot.defaultMinutes,
                          color: Palette.peach,
                          onPicked: (m) {
                            p.mealMinutes[slot.id] = m;
                            p.save();
                          },
                        ),
                      Switch(
                        value: p.mealOn[slot.id] ?? false,
                        onChanged: (v) {
                          p.mealOn[slot.id] = v;
                          p.save();
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- Live test: proves the buttons work and reaches a paired watch
          SoftCard(
            onTap: Reminders.testReminder,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: Palette.mint.withValues(alpha: .14),
            child: Row(
              children: [
                const Text('⌚', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Send a test reminder',
                          style: theme.textTheme.titleMedium),
                      Text(
                          'Posts a water reminder right now, buttons and all. '
                          'It should also appear on a paired watch.',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.send_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          if (showChime) ...[
            const SizedBox(height: 10),

            // ---- Sound preview
            SoftCard(
              onTap: Reminders.playChime,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              color: Palette.lavender.withValues(alpha: .14),
              child: Row(
                children: [
                  const Text('🔔', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Play the chime',
                            style: theme.textTheme.titleMedium),
                        Text(
                            'Sends a test notification with the reminder sound.',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.play_circle_outline_rounded,
                      color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.color,
    required this.child,
  });
  final String emoji;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      color: color.withValues(alpha: .12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          if (value) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill(
      {this.label,
      required this.minutes,
      required this.color,
      required this.onPicked});
  final String? label;
  final int minutes;
  final Color color;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    return Pill(
      emoji: '🕒',
      dense: true,
      color: color,
      label: label == null
          ? ReminderPrefs.fmt(minutes)
          : '$label ${ReminderPrefs.fmt(minutes)}',
      onTap: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        );
        if (t != null) onPicked(t.hour * 60 + t.minute);
      },
    );
  }
}
