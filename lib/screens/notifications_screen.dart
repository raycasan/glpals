import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Everything the app has reminded you about, and what is queued next.
///
/// Android does not let an app read back its own posted notifications, so this
/// is built from the schedule itself: entries in the past were delivered,
/// entries in the future are still due.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotifLog> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = await AppDb.instance.notifs();
    if (mounted) {
      setState(() {
        _all = n;
        _loading = false;
      });
    }
  }

  Future<void> _clear() async {
    final ok = await confirmDelete(
      context,
      title: 'Clear history?',
      body: 'Past reminders are removed from this list. Upcoming ones stay.',
      confirmLabel: 'Clear',
    );
    if (!ok) return;
    await AppDb.instance.clearNotifHistory();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final past = _all.where((n) => n.at.isBefore(now)).toList();
    final upcoming = _all.where((n) => !n.at.isBefore(now)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders 🔔'),
        actions: [
          IconButton(
            onPressed: () async {
              await Reminders.testReminder();
              await Future<void>.delayed(const Duration(milliseconds: 400));
              await _load();
            },
            icon: const Icon(Icons.send_rounded),
            tooltip: 'Send a test reminder',
          ),
          if (past.isNotEmpty)
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear history',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  if (_all.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: EmptyState(
                        emoji: '🔔',
                        title: 'Nothing yet',
                        body:
                            'Turn a reminder on in Settings and it will show up here, '
                            'both what is coming and what has already been sent.',
                      ),
                    ),
                  if (upcoming.isNotEmpty) ...[
                    const SectionTitle('Coming up', emoji: '⏭️'),
                    for (final n in upcoming)
                      _NotifTile(log: n, upcoming: true),
                    const SizedBox(height: 18),
                  ],
                  if (past.isNotEmpty) ...[
                    const SectionTitle('Already sent', emoji: '📜'),
                    for (final n in past) _NotifTile(log: n, upcoming: false),
                  ],
                ],
              ),
            ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.log, required this.upcoming});
  final NotifLog log;
  final bool upcoming;

  static const _look = {
    'shot': ('💉', Palette.coral),
    'countdown': ('⏳', Palette.lavender),
    'water': ('💧', Palette.sky),
    'meal': ('🍽️', Palette.sunshine),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (emoji, color) = _look[log.kind] ?? ('🔔', Palette.mint);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        color: upcoming ? null : color.withValues(alpha: .08),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color.withValues(alpha: .16)),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(log.body,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        upcoming
                            ? 'in ${fmtCountdown(log.at.difference(DateTime.now()))} · ${DateFormat('EEE h:mm a').format(log.at)}'
                            : '${relativeDay(log.at)} · ${DateFormat('h:mm a').format(log.at)}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant),
                      ),
                      if (log.action != null) ...[
                        const SizedBox(width: 8),
                        Pill(
                            label: log.action!,
                            emoji: '✅',
                            dense: true,
                            color: Palette.mint),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
