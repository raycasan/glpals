import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Facial mood of a pal.
enum PalMood { normal, sleepy, happy }

/// A code-drawn companion: one kawaii character per species, five growth
/// stages, animated from a phase value so the caller owns the tickers.
///
/// Everything is drawn in a 100x100 unit box centred on the origin, so a pal
/// scales cleanly to any [size].
class PalArt extends StatelessWidget {
  const PalArt({
    super.key,
    required this.species,
    required this.stage,
    required this.size,
    required this.phase,
    this.blink = 0,
    this.pop = 0,
    this.mood = PalMood.normal,
  });

  /// Species id: fish, bird, cat, dog, bear, bunny.
  final String species;

  /// Growth stage 0-4; stage 0 is the pre-hatch object.
  final int stage;
  final double size;

  /// Idle loop phase 0-1.
  final double phase;

  /// Eyelid closure 0 (open) to 1 (closed).
  final double blink;

  /// Tap reaction 0-1: 0 is idle, 1 is the peak of the bounce.
  final double pop;
  final PalMood mood;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _PalPainter(
          species: species,
          stage: stage,
          phase: phase,
          blink: blink,
          pop: pop,
          mood: mood,
        ),
      );
}

class _Look {
  const _Look(this.body, this.line, this.accent);
  final Color body;
  final Color line;
  final Color accent;
}

const _looks = <String, _Look>{
  'ocean': _Look(Color(0xFF5FD3F3), Color(0xFF1E8FB8), Color(0xFFB9EEFF)),
  'bird': _Look(Color(0xFFFFD166), Color(0xFFD99A16), Color(0xFFFF9F43)),
  'cat': _Look(Color(0xFFFFB26B), Color(0xFFD9782A), Color(0xFFFFE0C2)),
  'dog': _Look(Color(0xFFF2C28B), Color(0xFFB97D3E), Color(0xFFFFF3E3)),
  'bear': _Look(Color(0xFFB77A4E), Color(0xFF7D4E2B), Color(0xFFE9C9A6)),
  'bunny': _Look(Color(0xFFFFF3E8), Color(0xFFC98E9C), Color(0xFFFFC2CF)),
};

const _ink = Color(0xFF2B2D42);
const _blush = Color(0x99FF8FA3);
const _cream = Color(0xFFFFF6EC);
const _gold = Color(0xFFFFC94D);
const _berry = Color(0xFFEF476F);

class _PalPainter extends CustomPainter {
  _PalPainter({
    required this.species,
    required this.stage,
    required this.phase,
    required this.blink,
    required this.pop,
    required this.mood,
  });

  final String species;
  final int stage;
  final double phase;
  final double blink;
  final double pop;
  final PalMood mood;

  late final _Look look = _looks[species] ?? _looks['dog']!;
  late final double w = phase * 2 * math.pi;
  late final double sw = math.sin(w);

  Paint _fill(Color c) => Paint()
    ..color = c
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  Paint _line(Color c, [double width = 3.2]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  void _shape(Canvas c, Path p, Color fill, Color line, [double width = 3.2]) {
    c.drawPath(p, _fill(fill));
    c.drawPath(p, _line(line, width));
  }

  void _oval(
      Canvas c, Offset center, double rw, double rh, Color fill, Color line) {
    final r = Rect.fromCenter(center: center, width: rw * 2, height: rh * 2);
    c.drawOval(r, _fill(fill));
    c.drawOval(r, _line(line));
  }

  /// Merges overlapping pieces into one outline so no inner edges show.
  Path _union(Iterable<Path> parts) =>
      parts.reduce((a, b) => Path.combine(PathOperation.union, a, b));

  Path _ovalPath(Offset center, double rw, double rh) => Path()
    ..addOval(Rect.fromCenter(center: center, width: rw * 2, height: rh * 2));

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 100;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + 4 * unit);
    canvas.scale(unit);

    // Idle bob and breathing, plus the tap bounce.
    final bounce = math.sin(pop * math.pi);
    final scale = const [0.84, 0.72, 0.86, 0.95, 1.0][stage.clamp(0, 4)] *
        (1 + 0.14 * bounce);
    canvas.translate(0, sw * 2.2 - bounce * 10);
    canvas.scale(scale * (1 + 0.025 * sw), scale * (1 - 0.025 * sw));
    // Species with tall ears or a long tail are drawn a little smaller so
    // nothing leaves the box.
    final fit = switch (species) {
      'bunny' => 0.8,
      'ocean' => 0.86,
      _ => 1.0,
    };
    canvas.scale(fit);

    if (stage == 0) {
      _paintObject(canvas);
    } else {
      switch (species) {
        case 'ocean':
          _paintFish(canvas);
        case 'bird':
          _paintBird(canvas);
        case 'cat':
          _paintCat(canvas);
        case 'bunny':
          _paintBunny(canvas);
        case 'bear':
          _paintBear(canvas);
        default:
          _paintDog(canvas);
      }
      _accessory(canvas);
    }
    if (pop > 0) _hearts(canvas, bounce);
    canvas.restore();
  }

  // ---- shared face ----

  void _face(Canvas c,
      {double eyeY = -4,
      double eyeGap = 14,
      double eyeR = 6.2,
      double mouthY = 11,
      bool drawMouth = true,
      double blushY = 6,
      double blushX = 23}) {
    // Blush.
    c.drawCircle(Offset(-blushX, blushY), 6, _fill(_blush));
    c.drawCircle(Offset(blushX, blushY), 6, _fill(_blush));

    for (final sx in [-1.0, 1.0]) {
      final ex = sx * eyeGap;
      switch (mood) {
        case PalMood.sleepy:
          final p = Path()
            ..moveTo(ex - eyeR, eyeY)
            ..quadraticBezierTo(ex, eyeY + eyeR * 1.1, ex + eyeR, eyeY);
          c.drawPath(p, _line(_ink, 2.8));
        case PalMood.happy:
          final p = Path()
            ..moveTo(ex - eyeR, eyeY + 2)
            ..quadraticBezierTo(ex, eyeY - eyeR * 1.2, ex + eyeR, eyeY + 2);
          c.drawPath(p, _line(_ink, 2.8));
        case PalMood.normal:
          final open = (1 - blink).clamp(0.08, 1.0);
          final rect = Rect.fromCenter(
              center: Offset(ex, eyeY),
              width: eyeR * 2,
              height: eyeR * 2 * open);
          c.drawOval(rect, _fill(_ink));
          if (open > 0.5) {
            c.drawCircle(Offset(ex - eyeR * .32, eyeY - eyeR * .35), eyeR * .34,
                _fill(Colors.white));
          }
      }
    }

    if (!drawMouth) return;
    switch (mood) {
      case PalMood.happy:
        final m = Path()
          ..moveTo(-8, mouthY - 2)
          ..quadraticBezierTo(0, mouthY + 12, 8, mouthY - 2)
          ..close();
        c.drawPath(m, _fill(const Color(0xFF9B2C3B)));
        c.drawPath(m, _line(_ink, 2.4));
        c.save();
        c.clipPath(m);
        c.drawCircle(
            Offset(0, mouthY + 9), 5.5, _fill(const Color(0xFFFF8FA3)));
        c.restore();
      case PalMood.sleepy:
        c.drawCircle(Offset(0, mouthY + 2), 2.2, _fill(_ink));
      case PalMood.normal:
        final m = Path()
          ..moveTo(-7, mouthY - 1)
          ..quadraticBezierTo(0, mouthY + 5, 7, mouthY - 1);
        c.drawPath(m, _line(_ink, 2.6));
    }
  }

  // ---- species ----

  void _paintFish(Canvas c) {
    final fl = look.line;
    final wag = sw * 0.16;
    // Tail fin (behind body), swaying.
    c.save();
    c.translate(31, 0);
    c.rotate(wag);
    final tail = Path()
      ..moveTo(0, 0)
      ..lineTo(20, -17)
      ..quadraticBezierTo(14, 0, 20, 17)
      ..close();
    _shape(c, tail, look.accent, fl);
    c.restore();
    // Dorsal fin.
    final dorsal = Path()
      ..moveTo(-10, -25)
      ..quadraticBezierTo(2, -44, 14, -24)
      ..close();
    _shape(c, dorsal, look.accent, fl);
    // Body.
    _oval(c, Offset.zero, 38, 29, look.body, fl);
    // Side fin, low and to the side so it stays clear of the mouth.
    c.save();
    c.translate(22, 21);
    c.rotate(-0.8 + sw * 0.12);
    _oval(c, Offset.zero, 9, 4.5, look.accent, fl);
    c.restore();
    // Bubbles rising from the mouth side.
    if (stage >= 2) {
      final rise = phase * 22;
      c.drawCircle(Offset(-44, -6 - rise), 2.6 + stage * .3,
          _line(Colors.white.withValues(alpha: .85), 1.6));
      c.drawCircle(Offset(-49, 10 - rise * .6), 1.8,
          _line(Colors.white.withValues(alpha: .7), 1.4));
    }
    _face(c, eyeGap: 12, eyeY: -6, blushX: 20, blushY: 5, mouthY: 10);
  }

  void _paintBird(Canvas c) {
    final fl = look.line;
    final flap = sw * 0.22;
    // Wings.
    for (final sx in [-1.0, 1.0]) {
      c.save();
      c.translate(sx * 26, 2);
      c.rotate(sx * (0.35 + flap));
      _oval(c, Offset(sx * 8, 6), 9, 15, look.accent, fl);
      c.restore();
    }
    // Feet.
    for (final sx in [-1.0, 1.0]) {
      final foot = Path()
        ..moveTo(sx * 10, 30)
        ..lineTo(sx * 10, 38)
        ..moveTo(sx * 4, 39)
        ..lineTo(sx * 10, 38)
        ..lineTo(sx * 16, 39);
      c.drawPath(foot, _line(const Color(0xFFFF8C42), 2.8));
    }
    // Body.
    c.drawCircle(Offset.zero, 33, _fill(look.body));
    c.drawCircle(Offset.zero, 33, _line(fl));
    // Belly patch.
    _oval(c, const Offset(0, 12), 16, 12, _cream, _cream);
    // Tuft.
    final tuft = Path()
      ..moveTo(-4, -32)
      ..quadraticBezierTo(-8, -46, -2, -44)
      ..moveTo(0, -33)
      ..quadraticBezierTo(2, -48, 6, -44)
      ..moveTo(4, -32)
      ..quadraticBezierTo(12, -44, 12, -38);
    c.drawPath(tuft, _line(fl, 2.6));
    // Beak instead of a mouth.
    final beak = Path()
      ..moveTo(-6, 6)
      ..lineTo(6, 6)
      ..lineTo(0, 14)
      ..close();
    _shape(c, beak, const Color(0xFFFF8C42), const Color(0xFFD9651A), 2.2);
    _face(c, eyeGap: 12, eyeY: -6, drawMouth: false, blushY: 8, blushX: 22);
  }

  void _paintCat(Canvas c) {
    final fl = look.line;
    // Tail, wagging behind.
    c.save();
    c.translate(28, 18);
    c.rotate(sw * 0.35);
    final tail = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(18, -4, 16, -22);
    c.drawPath(tail, _line(fl, 9));
    c.drawPath(tail, _line(look.body, 5));
    c.restore();
    // Ears.
    for (final sx in [-1.0, 1.0]) {
      final ear = Path()
        ..moveTo(sx * 14, -26)
        ..lineTo(sx * 30, -48)
        ..lineTo(sx * 34, -18)
        ..close();
      _shape(c, ear, look.body, fl);
      final inner = Path()
        ..moveTo(sx * 19, -27)
        ..lineTo(sx * 28, -41)
        ..lineTo(sx * 30, -23)
        ..close();
      c.drawPath(inner, _fill(const Color(0xFFFFB3C1)));
    }
    // Head.
    _oval(c, Offset.zero, 35, 32, look.body, fl);
    // Stripes.
    if (stage >= 2) {
      final stripes = Path()
        ..moveTo(-6, -30)
        ..lineTo(-4, -20)
        ..moveTo(0, -32)
        ..lineTo(0, -21)
        ..moveTo(6, -30)
        ..lineTo(4, -20);
      c.drawPath(stripes, _line(fl, 2.4));
    }
    // Whiskers.
    for (final sx in [-1.0, 1.0]) {
      final wh = Path()
        ..moveTo(sx * 22, 6)
        ..lineTo(sx * 40, 2)
        ..moveTo(sx * 22, 11)
        ..lineTo(sx * 40, 13);
      c.drawPath(wh, _line(fl, 1.8));
    }
    // Nose.
    final nose = Path()
      ..moveTo(-3.5, 6)
      ..lineTo(3.5, 6)
      ..lineTo(0, 10)
      ..close();
    c.drawPath(nose, _fill(const Color(0xFFE8748A)));
    _face(c, eyeGap: 13, eyeY: -4, mouthY: 12, blushY: 8);
  }

  void _paintDog(Canvas c) {
    final fl = look.line;
    // Tail.
    c.save();
    c.translate(30, 16);
    c.rotate(-0.6 + sw * 0.45);
    _oval(c, const Offset(8, 0), 10, 4.5, look.body, fl);
    c.restore();
    // Floppy ears, swinging.
    for (final sx in [-1.0, 1.0]) {
      c.save();
      c.translate(sx * 27, -18);
      c.rotate(sx * (0.18 + sw * 0.08));
      final ear = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(sx * 4, 16), width: 16, height: 40),
          const Radius.circular(9));
      c.drawRRect(ear, _fill(fl.withValues(alpha: .9)));
      c.drawRRect(ear, _line(fl));
      c.restore();
    }
    // Head.
    _oval(c, Offset.zero, 36, 33, look.body, fl);
    // Eye patch.
    if (stage >= 3) {
      c.drawCircle(const Offset(14, -5), 11, _fill(fl.withValues(alpha: .55)));
    }
    // Snout.
    _oval(c, const Offset(0, 12), 14, 10, look.accent, fl);
    _oval(c, const Offset(0, 6), 5, 3.8, _ink, _ink);
    // Tongue.
    if (stage >= 2 && mood != PalMood.sleepy) {
      final tongue = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(4, 21), width: 8, height: 10),
          const Radius.circular(4));
      c.drawRRect(tongue, _fill(const Color(0xFFFF8FA3)));
      c.drawRRect(tongue, _line(fl, 1.8));
    }
    _face(c, eyeGap: 14, eyeY: -6, drawMouth: false, blushY: 6, blushX: 25);
    // Mouth line under the nose.
    final m = Path()
      ..moveTo(0, 9)
      ..lineTo(0, 13)
      ..moveTo(-6, 13)
      ..quadraticBezierTo(0, 18, 6, 13);
    if (mood != PalMood.happy) c.drawPath(m, _line(_ink, 2.2));
  }

  void _paintBunny(Canvas c) {
    final fl = look.line;
    // Ears, bouncing.
    for (final sx in [-1.0, 1.0]) {
      c.save();
      c.translate(sx * 13, -26);
      c.rotate(sx * (0.12 + sw * 0.06));
      c.scale(1, 1 + sw * 0.05);
      _oval(c, const Offset(0, -24), 9, 26, look.body, fl);
      _oval(c, const Offset(0, -22), 4.5, 18, look.accent, look.accent);
      c.restore();
    }
    // Head with cheek fluff, merged so the outline runs around both.
    _shape(
        c,
        _union([
          _ovalPath(Offset.zero, 34, 31),
          _ovalPath(const Offset(-30, 8), 8, 6),
          _ovalPath(const Offset(30, 8), 8, 6),
        ]),
        look.body,
        fl);
    // Nose.
    final nose = Path()
      ..moveTo(-3.5, 6)
      ..lineTo(3.5, 6)
      ..lineTo(0, 10)
      ..close();
    c.drawPath(nose, _fill(const Color(0xFFE8748A)));
    // Teeth.
    if (stage >= 2 && mood != PalMood.sleepy) {
      final teeth = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, 17), width: 8, height: 6),
          const Radius.circular(1.5));
      c.drawRRect(teeth, _fill(Colors.white));
      c.drawRRect(teeth, _line(fl, 1.6));
      c.drawLine(const Offset(0, 14), const Offset(0, 20), _line(fl, 1.4));
    }
    _face(c, eyeGap: 13, eyeY: -4, mouthY: 12, blushY: 7, blushX: 22);
  }

  void _paintBear(Canvas c) {
    final fl = look.line;
    // Ears, wiggling.
    for (final sx in [-1.0, 1.0]) {
      c.save();
      c.translate(sx * 26, -26);
      c.rotate(sx * sw * 0.12);
      c.drawCircle(Offset.zero, 11, _fill(look.body));
      c.drawCircle(Offset.zero, 11, _line(fl));
      c.drawCircle(Offset.zero, 5.5, _fill(look.accent));
      c.restore();
    }
    // Scarf, tucked behind the head.
    if (stage >= 2) {
      final scarf = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, 30), width: 44, height: 14),
          const Radius.circular(7));
      c.drawRRect(scarf, _fill(_berry));
      c.drawRRect(scarf, _line(const Color(0xFFB2334F), 2.2));
    }
    // Head.
    _oval(c, Offset.zero, 36, 33, look.body, fl);
    // Snout.
    _oval(c, const Offset(0, 11), 15, 11, look.accent, fl);
    _oval(c, const Offset(0, 6), 5.5, 4, _ink, _ink);
    _face(c, eyeGap: 14, eyeY: -6, drawMouth: false, blushY: 6, blushX: 26);
    final m = Path()
      ..moveTo(0, 10)
      ..lineTo(0, 13)
      ..moveTo(-6, 13)
      ..quadraticBezierTo(0, 18, 6, 13);
    if (mood != PalMood.happy) c.drawPath(m, _line(_ink, 2.2));
  }

  // ---- stage 0: the pre-hatch object ----

  void _paintObject(Canvas c) {
    c.save();
    c.rotate(sw * 0.08);
    switch (species) {
      case 'cat':
        // Yarn ball.
        c.drawCircle(Offset.zero, 32, _fill(const Color(0xFFB9A6FF)));
        c.drawCircle(Offset.zero, 32, _line(const Color(0xFF7A62D9)));
        final thread = Path()
          ..moveTo(-30, -8)
          ..quadraticBezierTo(0, 22, 30, -6)
          ..moveTo(-24, 18)
          ..quadraticBezierTo(4, -28, 28, 14)
          ..moveTo(-10, -30)
          ..quadraticBezierTo(24, -4, 8, 30);
        c.drawPath(thread, _line(const Color(0xFF7A62D9), 2.2));
        c.drawLine(const Offset(26, 18), const Offset(46, 30),
            _line(const Color(0xFF7A62D9), 3));
      case 'dog':
        // Bone, merged into one silhouette.
        final bone = _union([
          Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: 52, height: 18),
                const Radius.circular(9))),
          for (final sx in [-1.0, 1.0]) ...[
            _ovalPath(Offset(sx * 26, -7), 10, 10),
            _ovalPath(Offset(sx * 26, 7), 10, 10),
          ],
        ]);
        _shape(c, bone, _cream, const Color(0xFFC9A98C));
      case 'bunny':
        // Carrot.
        final body = Path()
          ..moveTo(-16, -14)
          ..quadraticBezierTo(0, -22, 16, -14)
          ..quadraticBezierTo(6, 30, 0, 40)
          ..quadraticBezierTo(-6, 30, -16, -14)
          ..close();
        _shape(c, body, const Color(0xFFFF8C42), const Color(0xFFD9651A));
        final lines = Path()
          ..moveTo(-8, 0)
          ..lineTo(6, -2)
          ..moveTo(-6, 12)
          ..lineTo(5, 10);
        c.drawPath(lines, _line(const Color(0xFFD9651A), 2));
        for (final a in [-0.5, 0.0, 0.5]) {
          c.save();
          c.translate(0, -18);
          c.rotate(a + sw * 0.05);
          _oval(c, const Offset(0, -12), 5, 13, const Color(0xFF7ED957),
              const Color(0xFF3FA34D));
          c.restore();
        }
      case 'bear':
        // Honey pot.
        final pot = Path()
          ..moveTo(-26, -8)
          ..quadraticBezierTo(-34, 30, -12, 34)
          ..lineTo(12, 34)
          ..quadraticBezierTo(34, 30, 26, -8)
          ..close();
        _shape(c, pot, const Color(0xFFE9A54A), const Color(0xFFB2711E));
        // Drip first so the lip covers its top edge.
        // Drip hangs off the right rim, clear of the face.
        final drip = Path()
          ..moveTo(27, -8)
          ..quadraticBezierTo(33, 4, 27, 12)
          ..quadraticBezierTo(21, 4, 27, -8)
          ..close();
        c.drawPath(drip, _fill(const Color(0xFFF6C46B)));
        c.drawPath(drip, _line(const Color(0xFFB2711E), 2));
        final lip = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: const Offset(0, -12), width: 60, height: 14),
            const Radius.circular(7));
        c.drawRRect(lip, _fill(const Color(0xFFF6C46B)));
        c.drawRRect(lip, _line(const Color(0xFFB2711E)));
      case 'ocean':
        _paintRoe(c);
      default:
        // Egg (bird): plain and speckled, no crack.
        final egg = Path()
          ..moveTo(0, -36)
          ..cubicTo(22, -36, 30, -6, 30, 10)
          ..cubicTo(30, 28, 16, 38, 0, 38)
          ..cubicTo(-16, 38, -30, 28, -30, 10)
          ..cubicTo(-30, -6, -22, -36, 0, -36)
          ..close();
        _shape(c, egg, _cream, const Color(0xFFD9A066));
        final spots = [
          const Offset(-12, -6),
          const Offset(14, 12),
          const Offset(6, -18)
        ];
        for (final s in spots) {
          c.drawCircle(s, 4, _fill(look.body.withValues(alpha: .55)));
        }
    }
    // Objects keep a small cosy face.
    _face(c, eyeGap: 9, eyeY: 2, eyeR: 3.4, mouthY: 12, blushX: 16, blushY: 10);
    c.restore();
  }

  /// A cluster of glossy orange fish eggs; the big front one carries the face.
  void _paintRoe(Canvas c) {
    const fill = Color(0xFFFF8A3D);
    const edge = Color(0xFFD9531E);
    const glow = Color(0xFFFFC08A);
    void egg(Offset at, double r) {
      final rect = Rect.fromCircle(center: at, radius: r);
      c.drawCircle(
          at,
          r,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(-0.3, -0.35),
              colors: [glow, fill, Color(0xFFF26B1F)],
              stops: [0, .55, 1],
            ).createShader(rect));
      c.drawCircle(at, r, _line(edge, 2.4));
      c.drawCircle(Offset(at.dx - r * .38, at.dy - r * .4), r * .22,
          _fill(Colors.white.withValues(alpha: .9)));
    }

    // Back row, then the sides, then the big front egg.
    egg(const Offset(-16, -20), 12);
    egg(const Offset(16, -20), 12);
    egg(const Offset(0, -27), 12);
    egg(const Offset(-26, 4), 12);
    egg(const Offset(26, 4), 12);
    egg(const Offset(-15, 24), 12);
    egg(const Offset(15, 24), 12);
    egg(const Offset(0, 4), 22);
  }

  // ---- accessories by stage ----

  void _accessory(Canvas c) {
    if (stage == 2) {
      // Day 7: gold circlet with a little star ornament.
      _goldBand(c);
      _star(c, const Offset(0, -31), 5.5, _gold, const Color(0xFFC9931A));
      for (final x in [-12.0, 12.0]) {
        c.drawCircle(Offset(x, -27), 2, _fill(_gold));
        c.drawCircle(Offset(x, -27), 2, _line(const Color(0xFFC9931A), 1.2));
      }
    } else if (stage == 3) {
      // Day 14: the circlet now carries a faceted gemstone.
      _goldBand(c);
      _gem(c, const Offset(0, -31));
    } else if (stage >= 4) {
      // Day 30: gold crown.
      // Base of the crown rests on the head; the bunny's ears rise behind it.
      final top = species == 'ocean' ? -40.0 : -44.0;
      final crown = Path()
        ..moveTo(-16, top + 14)
        ..lineTo(-16, top)
        ..lineTo(-8, top + 8)
        ..lineTo(0, top - 4)
        ..lineTo(8, top + 8)
        ..lineTo(16, top)
        ..lineTo(16, top + 14)
        ..close();
      _shape(c, crown, _gold, const Color(0xFFC9931A), 2.2);
      for (final x in [-8.0, 0.0, 8.0]) {
        c.drawCircle(Offset(x, top + 9), 2, _fill(_berry));
      }
    }
  }

  /// Thin gold band following the top of the head.
  void _goldBand(Canvas c) {
    final band = Path()
      ..moveTo(-26, -18)
      ..quadraticBezierTo(0, -42, 26, -18);
    c.drawPath(band, _line(const Color(0xFFC9931A), 6));
    c.drawPath(band, _line(_gold, 3.4));
  }

  /// Five-point star.
  void _star(Canvas c, Offset at, double r, Color fill, Color edge) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final a = -math.pi / 2 + k * math.pi / 5;
      final rr = k.isEven ? r : r * .45;
      final pt = Offset(at.dx + math.cos(a) * rr, at.dy + math.sin(a) * rr);
      if (k == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    _shape(c, path, fill, edge, 1.6);
  }

  /// Faceted ruby with a highlight and a sparkle.
  void _gem(Canvas c, Offset at) {
    final gem = Path()
      ..moveTo(at.dx, at.dy - 9)
      ..lineTo(at.dx + 7, at.dy - 2)
      ..lineTo(at.dx, at.dy + 8)
      ..lineTo(at.dx - 7, at.dy - 2)
      ..close();
    _shape(c, gem, _berry, const Color(0xFFB2334F), 1.8);
    // Upper facet catches the light.
    final facet = Path()
      ..moveTo(at.dx, at.dy - 9)
      ..lineTo(at.dx + 7, at.dy - 2)
      ..lineTo(at.dx - 7, at.dy - 2)
      ..close();
    c.drawPath(facet, _fill(const Color(0x66FFFFFF)));
    c.drawLine(Offset(at.dx - 7, at.dy - 2), Offset(at.dx + 7, at.dy - 2),
        _line(const Color(0xFFB2334F), 1.2));
    // Sparkle.
    final sp = Offset(at.dx + 9, at.dy - 10);
    final sparkle = Path()
      ..moveTo(sp.dx, sp.dy - 4)
      ..quadraticBezierTo(sp.dx, sp.dy, sp.dx + 4, sp.dy)
      ..quadraticBezierTo(sp.dx, sp.dy, sp.dx, sp.dy + 4)
      ..quadraticBezierTo(sp.dx, sp.dy, sp.dx - 4, sp.dy)
      ..quadraticBezierTo(sp.dx, sp.dy, sp.dx, sp.dy - 4)
      ..close();
    c.drawPath(sparkle, _fill(Colors.white));
  }

  void _hearts(Canvas c, double bounce) {
    final rise = pop * 26;
    for (final h in [const Offset(-30, -36), const Offset(32, -30)]) {
      final heart = Path()
        ..moveTo(h.dx, h.dy - rise + 4)
        ..cubicTo(h.dx - 8, h.dy - rise - 6, h.dx - 2, h.dy - rise - 12, h.dx,
            h.dy - rise - 4)
        ..cubicTo(h.dx + 2, h.dy - rise - 12, h.dx + 8, h.dy - rise - 6, h.dx,
            h.dy - rise + 4)
        ..close();
      c.drawPath(heart, _fill(_berry.withValues(alpha: (1 - pop).clamp(0, 1))));
    }
  }

  @override
  bool shouldRepaint(_PalPainter old) =>
      old.phase != phase ||
      old.blink != blink ||
      old.pop != pop ||
      old.mood != mood ||
      old.stage != stage ||
      old.species != species;
}
