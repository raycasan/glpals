import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Branded splash shown while [init] runs. Continues the Android system
/// splash (same orange, same mascot) so the handoff is seamless, holds for at
/// least [minimum], then fades into [next].
class SplashScreen<T> extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.init,
    required this.next,
    this.minimum = const Duration(milliseconds: 1700),
  });

  final Future<T> Function() init;
  final Widget Function(T result) next;
  final Duration minimum;

  @override
  State<SplashScreen<T>> createState() => _SplashScreenState<T>();
}

class _SplashScreenState<T> extends State<SplashScreen<T>>
    with TickerProviderStateMixin {
  static const _orangeDeep = Color(0xFFF9812C);
  static const _orangeLight = Color(0xFFFFC58A);

  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..forward();
  late final AnimationController _loop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  late final Animation<double> _pop = CurvedAnimation(
      parent: _intro, curve: const Interval(0, .6, curve: Curves.elasticOut));
  late final Animation<double> _wash = CurvedAnimation(
      parent: _intro, curve: const Interval(0, .7, curve: Curves.easeOut));
  late final Animation<double> _title = CurvedAnimation(
      parent: _intro,
      curve: const Interval(.3, .75, curve: Curves.easeOutCubic));
  late final Animation<double> _tagline = CurvedAnimation(
      parent: _intro,
      curve: const Interval(.5, .95, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final started = DateTime.now();
    final result = await widget.init();
    final left = widget.minimum - DateTime.now().difference(started);
    if (left > Duration.zero) await Future.delayed(left);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => widget.next(result),
      transitionDuration: const Duration(milliseconds: 550),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AnimatedBuilder(
        animation: _intro,
        builder: (context, _) {
          final top = Color.lerp(_orangeDeep, _orangeLight, _wash.value)!;
          // Material ancestor so text picks up the app font instead of the
          // yellow-underlined fallback.
          return Material(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [top, _orangeDeep],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Soft highlight in the top-left corner.
                  Positioned(
                    top: -120,
                    left: -80,
                    child: Opacity(
                      opacity: .22 * _wash.value,
                      child: Container(
                        width: 360,
                        height: 360,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                              colors: [Colors.white, Colors.transparent]),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      const Spacer(flex: 19),
                      _Mascot(pop: _pop, loop: _loop),
                      const SizedBox(height: 28),
                      _Rise(
                        t: _title,
                        child: const Text(
                          'GLPals',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.2,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _Rise(
                        t: _tagline,
                        child: Text(
                          'Your buddy for the GLP-1 journey',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: .92),
                          ),
                        ),
                      ),
                      const Spacer(flex: 10),
                      FadeTransition(
                          opacity: _tagline, child: _Dots(loop: _loop)),
                      const SizedBox(height: 48),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Mascot popping in with an elastic scale, then bobbing gently.
class _Mascot extends StatelessWidget {
  const _Mascot({required this.pop, required this.loop});
  final Animation<double> pop;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pop, loop]),
      builder: (context, _) {
        final bob = Curves.easeInOut.transform(
                loop.value < .5 ? loop.value * 2 : (1 - loop.value) * 2) *
            8;
        final scale = .55 + .45 * pop.value;
        return Transform.translate(
          offset: Offset(0, -bob),
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Halo behind the mascot.
                  Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .16),
                    ),
                  ),
                  Image.asset('assets/icon/glpals_buddy.png',
                      width: 220,
                      height: 220,
                      filterQuality: FilterQuality.high),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fades and slides a child upward as [t] goes 0 to 1.
class _Rise extends StatelessWidget {
  const _Rise({required this.t, required this.child});
  final Animation<double> t;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: t,
        child: SlideTransition(
          position:
              Tween(begin: const Offset(0, .5), end: Offset.zero).animate(t),
          child: child,
        ),
      );
}

/// Three dots pulsing in sequence while startup work runs.
class _Dots extends StatelessWidget {
  const _Dots({required this.loop});
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: loop,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Opacity(
                  opacity: .35 +
                      .65 *
                          (1 - ((loop.value * 3 - i) % 3 / 3).clamp(0.0, 1.0)),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      );
}
