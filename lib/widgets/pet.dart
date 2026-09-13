import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../db.dart';
import '../xp.dart';
import 'pal_art.dart';

/// Hours the pals nap: 10 PM until 7 AM. Outside this window they are awake
/// however the day is going.
bool get isPalBedtime {
  final h = DateTime.now().hour;
  return h >= 22 || h < 7;
}

/// One growth stage of a companion, unlocked by total experience.
class PetStage {
  const PetStage(this.emoji, this.name, this.minXp);
  final String emoji;
  final String name;

  /// Experience needed to reach this stage.
  final int minXp;

  static String mood(int streak) {
    if (streak == 0) return 'Log a check-in today to help me grow!';
    if (streak < 3) return "I'm just getting started. Keep going!";
    if (streak < 7) return 'Growing nicely. $streak days in a row!';
    if (streak < 14) return "Going strong. You're consistent!";
    if (streak < 30) return 'Look at us go! $streak days and counting.';
    return 'Legendary streak. Nothing can stop us!';
  }

  /// Face for the thought bubble. Tracks consistency only, never weight or
  /// symptoms. Sleeping is a time-of-day thing, not a scolding for a missed
  /// check-in: the pal only naps between 10 PM and 7 AM.
  static String moodFor({required int streak, required bool checkedInToday}) {
    if (isPalBedtime) return '💤';
    if (const {3, 7, 14, 30}.contains(streak)) return '🎉';
    return checkedInToday ? '😊' : '👀';
  }
}

/// A selectable companion with five growth stages that unlock with experience.
class PetSpecies {
  const PetSpecies(
      {required this.id, required this.name, required this.stages});
  final String id;
  final String name;
  final List<PetStage> stages;

  /// Emoji used to represent this companion in pickers and avatars.
  String get icon => stages[1].emoji;

  PetStage stageFor(int xp) => stages[Xp.stageIndexFor(xp)];

  PetStage? next(PetStage current) {
    final i = stages.indexOf(current);
    return i < stages.length - 1 ? stages[i + 1] : null;
  }

  double progress(int xp) => Xp.progress(xp);

  static const all = [
    PetSpecies(id: 'ocean', name: 'Fish', stages: [
      PetStage('🥚', 'Buddy Egg', 0),
      PetStage('🐠', 'Little Fry', 150),
      PetStage('🐟', 'Steady Fish', 500),
      PetStage('🐬', 'Happy Dolphin', 1200),
      PetStage('🐋', 'Mighty Whale', 2500),
    ]),
    PetSpecies(id: 'bird', name: 'Bird', stages: [
      PetStage('🥚', 'Cozy Egg', 0),
      PetStage('🐣', 'Hatchling', 150),
      PetStage('🐥', 'Fluffy Chick', 500),
      PetStage('🐦', 'Songbird', 1200),
      PetStage('🦅', 'Soaring Eagle', 2500),
    ]),
    PetSpecies(id: 'cat', name: 'Cat', stages: [
      PetStage('🧶', 'Yarn Ball', 0),
      PetStage('🐱', 'Curious Kitten', 150),
      PetStage('🐈', 'Sleek Cat', 500),
      PetStage('🐯', 'Bold Tiger', 1200),
      PetStage('🦁', 'Proud Lion', 2500),
    ]),
    PetSpecies(id: 'dog', name: 'Dog', stages: [
      PetStage('🦴', 'Chew Toy', 0),
      PetStage('🐶', 'Playful Puppy', 150),
      PetStage('🐕', 'Good Dog', 500),
      PetStage('🦮', 'Loyal Guide', 1200),
      PetStage('🐕‍🦺', 'Top Dog', 2500),
    ]),
    PetSpecies(id: 'bear', name: 'Bear', stages: [
      PetStage('🍯', 'Honey Pot', 0),
      PetStage('🧸', 'Teddy Cub', 150),
      PetStage('🐻', 'Cozy Bear', 500),
      PetStage('🐻‍❄️', 'Polar Pal', 1200),
      PetStage('🐼', 'Panda Legend', 2500),
    ]),
    PetSpecies(id: 'bunny', name: 'Bunny', stages: [
      PetStage('🥕', 'Carrot Patch', 0),
      PetStage('🐰', 'Baby Bunny', 150),
      PetStage('🐇', 'Hoppy Rabbit', 500),
      PetStage('🦘', 'Super Hopper', 1200),
      PetStage('🦄', 'Mythic Hopper', 2500),
    ]),
  ];

  static PetSpecies byId(String? id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);
}

/// Currently selected companion. Change via [PetPrefs.set].
final petSpecies = ValueNotifier<PetSpecies>(PetSpecies.all.first);

class PetPrefs {
  static const _key = 'pet_species';

  static Future<void> load() async {
    petSpecies.value = PetSpecies.byId(await AppDb.instance.getSetting(_key));
  }

  static Future<void> set(PetSpecies s) async {
    petSpecies.value = s;
    await AppDb.instance.setSetting(_key, s.id);
  }
}

/// Bobbing, gently rotating pet with a soft glow and sparkles.
class PetAvatar extends StatefulWidget {
  const PetAvatar(
      {super.key,
      required this.species,
      required this.xp,
      this.size = 120,
      this.mood});
  final PetSpecies species;

  /// Total experience, which decides the stage drawn.
  final int xp;
  final double size;

  /// Optional emoji shown in a small thought bubble (e.g. 💤 before today's check-in).
  final String? mood;

  @override
  State<PetAvatar> createState() => _PetAvatarState();
}

class _PetAvatarState extends State<PetAvatar> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4300),
  )..repeat();
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void dispose() {
    _c.dispose();
    _blink.dispose();
    _pop.dispose();
    super.dispose();
  }

  /// Eyelid closure from the blink cycle: a quick shut near the end of it.
  double get _blinkAmount {
    final v = _blink.value;
    if (v < .9 || v > .97) return 0;
    return math.sin((v - .9) / .07 * math.pi);
  }

  /// One of three "z" letters drifting up and to the right from the pal's
  /// head, each on its own phase of the idle loop.
  Widget _sleepZ(int i, double size) {
    final p = (_c.value + i / 3) % 1.0;
    final ease = Curves.easeOut.transform(p);
    final x = size * (0.60 + 0.26 * ease);
    final y = size * (0.36 - 0.34 * ease);
    final opacity = math.sin(p * math.pi).clamp(0.0, 1.0);
    final fontSize = size * (0.10 + 0.09 * ease);
    return Positioned(
      left: x,
      top: y,
      child: Opacity(
        opacity: opacity,
        child: Text(
          'z',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1,
            shadows: const [
              Shadow(
                  color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }

  PalMood get _mood => switch (widget.mood) {
        '💤' => PalMood.sleepy,
        '🎉' => PalMood.happy,
        _ => PalMood.normal,
      };

  @override
  Widget build(BuildContext context) {
    final stage = widget.species.stageFor(widget.xp);
    final stageIndex = widget.species.stages.indexOf(stage);
    final size = widget.size;
    return GestureDetector(
      onTap: () {
        if (!_pop.isAnimating) _pop.forward(from: 0);
      },
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, _blink, _pop]),
          builder: (_, __) {
            final t = _c.value * 2 * math.pi;
            const bob = 0.0;
            final tilt = math.sin(t + 1) * 0.04;
            final sparkle = (math.sin(t * 1.5) + 1) / 2;
            final pal = AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: PalArt(
                key: ValueKey('${widget.species.id}-$stageIndex'),
                species: widget.species.id,
                stage: stageIndex,
                size: size * .92,
                phase: _c.value,
                blink: _blinkAmount,
                pop: _pop.value,
                mood: _mood,
              ),
            );
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: size * .92,
                  height: size * .92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: .45),
                        Colors.white.withValues(alpha: .12),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0, .6, 1],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, bob),
                  child: Transform.rotate(
                    angle: tilt,
                    child: pal,
                  ),
                ),
                // Top-right sparkle makes way for the sleep z's.
                if (widget.mood != '💤')
                  Positioned(
                    top: size * .08,
                    right: size * .1,
                    child: Opacity(
                      opacity: sparkle,
                      child: Text('✨', style: TextStyle(fontSize: size * .16)),
                    ),
                  ),
                if (widget.mood == '💤')
                  for (var i = 0; i < 3; i++) _sleepZ(i, size)
                else if (widget.mood != null)
                  Positioned(
                    top: size * .04,
                    right: size * .02,
                    child: Transform.scale(
                      scale: 1 + .08 * math.sin(t * 2),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .12),
                                blurRadius: 6,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Text(widget.mood!,
                            style: TextStyle(fontSize: size * .17, height: 1)),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: size * .14,
                  left: size * .06,
                  child: Opacity(
                    opacity: 1 - sparkle,
                    child: Text('✨', style: TextStyle(fontSize: size * .12)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
