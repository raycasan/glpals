import 'package:flutter/material.dart';

import '../xp.dart';
import 'pal_art.dart';
import 'pet.dart';

/// Every growth stage of a companion on one line, with the current one
/// highlighted and the experience each needs.
///
/// It never scrolls: the whole journey has to be readable at a glance, so the
/// stages share the available width and the art shrinks to fit rather than
/// running off the edge. A track behind the circles fills as experience is
/// earned, which also replaces the chevrons that used to eat the space.
class PalEvolution extends StatefulWidget {
  const PalEvolution({super.key, required this.species, required this.xp});
  final PetSpecies species;

  /// Total experience earned so far.
  final int xp;

  @override
  State<PalEvolution> createState() => _PalEvolutionState();
}

class _PalEvolutionState extends State<PalEvolution>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stages = widget.species.stages;
    final current = widget.species.stageFor(widget.xp);
    final currentIndex = stages.indexOf(current);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cell = width / stages.length;
        // Leaves a visible gap between circles for the connectors, while
        // keeping the art big enough to still read as the companion.
        final diameter = (cell - 16).clamp(28.0, 56.0);
        final compact = cell < 62;
        final gap = cell - diameter;

        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Stack(
            children: [
              // Connectors live in the gaps rather than behind the circles, so
              // the circles can stay translucent and sit on any background.
              for (var i = 0; i < stages.length - 1; i++)
                Positioned(
                  left: (i + 0.5) * cell + diameter / 2 + 2,
                  width: gap - 4,
                  top: diameter / 2 - 1.5,
                  child: _Connector(
                    // Full once the next stage is reached, part-filled while
                    // working towards it, empty beyond.
                    fill: i < currentIndex
                        ? 1
                        : i == currentIndex
                            ? Xp.progress(widget.xp)
                            : 0,
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < stages.length; i++)
                    Expanded(
                      child: _EvolutionCell(
                        species: widget.species,
                        index: i,
                        diameter: diameter,
                        compact: compact,
                        phase: (_c.value + i * .17) % 1,
                        unlocked: widget.xp >= stages[i].minXp,
                        current: i == currentIndex,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The short line between two stages, filling as experience is earned.
class _Connector extends StatelessWidget {
  const _Connector({required this.fill});

  /// 0 to 1.
  final double fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 3,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          FractionallySizedBox(
            widthFactor: fill.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvolutionCell extends StatelessWidget {
  const _EvolutionCell({
    required this.species,
    required this.index,
    required this.diameter,
    required this.compact,
    required this.phase,
    required this.unlocked,
    required this.current,
  });
  final PetSpecies species;
  final int index;
  final double diameter;
  final bool compact;
  final double phase;
  final bool unlocked;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stage = species.stages[index];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: current
                ? scheme.primary.withValues(alpha: .22)
                : scheme.onSurface.withValues(alpha: .06),
            border:
                current ? Border.all(color: scheme.primary, width: 2) : null,
          ),
          child: Opacity(
            opacity: unlocked ? 1 : .45,
            child: PalArt(
              species: species.id,
              stage: index,
              size: diameter,
              phase: unlocked ? phase : .25,
              mood: unlocked ? PalMood.normal : PalMood.sleepy,
            ),
          ),
        ),
        const SizedBox(height: 5),
        // Two lines are always reserved so the experience figures underneath
        // line up, whether a name wraps or not.
        SizedBox(
          height: compact ? 25 : 27,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              stage.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                height: 1.15,
                fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                color: current ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ),
        Text(
          stage.minXp == 0
              ? 'start'
              : compact
                  ? '${stage.minXp}'
                  : '${stage.minXp} XP',
          maxLines: 1,
          style: TextStyle(
              fontSize: compact ? 10 : 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
