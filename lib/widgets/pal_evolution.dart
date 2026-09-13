import 'package:flutter/material.dart';

import 'pal_art.dart';
import 'pet.dart';

/// All growth stages of a companion in a row, with the current one
/// highlighted and the experience needed for each. Gently animated.
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
    final scheme = Theme.of(context).colorScheme;
    final current = widget.species.stageFor(widget.xp);
    final stages = widget.species.stages;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < stages.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 21),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                ),
              _EvolutionCell(
                species: widget.species,
                index: i,
                phase: (_c.value + i * .17) % 1,
                unlocked: widget.xp >= stages[i].minXp,
                current: stages[i] == current,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvolutionCell extends StatelessWidget {
  const _EvolutionCell({
    required this.species,
    required this.index,
    required this.phase,
    required this.unlocked,
    required this.current,
  });
  final PetSpecies species;
  final int index;
  final double phase;
  final bool unlocked;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stage = species.stages[index];
    return SizedBox(
      width: 74,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
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
                size: 58,
                phase: unlocked ? phase : .25,
                mood: unlocked ? PalMood.normal : PalMood.sleepy,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stage.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontSize: 11,
              height: 1.15,
              fontWeight: current ? FontWeight.w800 : FontWeight.w600,
              color: current ? scheme.primary : scheme.onSurface,
            ),
          ),
          Text(
            stage.minXp == 0 ? 'start' : '${stage.minXp} XP',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
