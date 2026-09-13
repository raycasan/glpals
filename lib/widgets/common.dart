import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// Rounded, softly shadowed container. Pass [gradient] for a hero card.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.gradient,
    this.onTap,
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bg =
        gradient == null ? (color ?? Theme.of(context).cardTheme.color) : null;
    final shadowColor =
        gradient != null ? gradient!.colors.first : Colors.black;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: gradient != null ? .28 : .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Selectable rounded chip with optional emoji or icon.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.color,
    this.icon,
    this.emoji,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;
  final IconData? icon;
  final String? emoji;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    final fg = selected ? Colors.white : Color.lerp(c, scheme.onSurface, .35)!;
    final fontSize = dense ? 12.5 : 14.5;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 10 : 14, vertical: dense ? 6 : 10),
        decoration: BoxDecoration(
          color: selected ? c : c.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: c.withValues(alpha: .35),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null)
              Text(emoji!, style: TextStyle(fontSize: fontSize + 2)),
            if (icon != null) Icon(icon, size: fontSize + 3, color: fg),
            if (emoji != null || icon != null) const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: fontSize,
                    color: fg)),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.emoji, this.trailing});
  final String text;
  final String? emoji;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Row(
        children: [
          if (emoji != null)
            Text('$emoji ', style: const TextStyle(fontSize: 18)),
          Text(text, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String emoji;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: .12),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 50)),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated circular progress ring with a centered child.
class GoalRing extends StatelessWidget {
  const GoalRing({
    super.key,
    required this.progress,
    required this.color,
    this.size = 64,
    this.stroke = 7,
    this.child,
  });

  final double progress;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0, 1)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, color, stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.stroke);
  final double progress;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final track = Paint()
      ..color = color.withValues(alpha: .15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, track);
    if (progress > 0) {
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * progress, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}

/// Colored circle marking an injection site: color by body part, letter for side.
class SiteBadge extends StatelessWidget {
  const SiteBadge(this.site, {super.key, this.size = 48});
  final String site;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = siteColor(site);
    final side = site.endsWith('L')
        ? 'L'
        : site.endsWith('R')
            ? 'R'
            : '•';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: c.withValues(alpha: .16)),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(siteEmoji(site), style: TextStyle(fontSize: size * .34)),
          Text(side,
              style: TextStyle(
                  fontSize: size * .22, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }
}

Color siteColor(String site) {
  if (site.startsWith('Abdomen')) return Palette.coral;
  if (site.startsWith('Thigh')) return Palette.mint;
  return Palette.lavender;
}

String siteEmoji(String site) {
  if (site.startsWith('Abdomen')) return '🫃';
  if (site.startsWith('Thigh')) return '🦵';
  return '💪';
}

const sideEffectEmoji = {
  'nausea': '🤢',
  'fatigue': '😴',
  'constipation': '🧱',
  'diarrhea': '🚽',
  'appetite_loss': '🍽️',
  'headache': '🤕',
};

const severityFaces = ['😊', '😕', '😣', '😖'];
const severityLabels = ['none', 'mild', 'moderate', 'severe'];
const severityColors = [
  Palette.mint,
  Palette.sunshine,
  Palette.peach,
  Palette.berry
];

String greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Still up? 🌙';
  if (h < 12) return 'Good morning 🌅';
  if (h < 17) return 'Good afternoon ☀️';
  return 'Good evening 🌙';
}

String relativeDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';
  return DateFormat('EEE, MMM d').format(d);
}

/// Asks before something is removed for good. Returns true on confirm.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Delete',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
              backgroundColor: Palette.berry, minimumSize: const Size(0, 44)),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Compact "2d 4h" / "3h 20m" / "45m" countdown, used on Home, in the widget
/// and in reminder text so they always read the same.
String fmtCountdown(Duration d) {
  if (d.isNegative) return 'now';
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return 'now';
}

/// yyyy-MM-dd key used for day-scoped rows and lookups.
String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Strips the time part, keeping the calendar day.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String fmtDose(double d) =>
    d == d.roundToDouble() ? d.toInt().toString() : d.toString();
