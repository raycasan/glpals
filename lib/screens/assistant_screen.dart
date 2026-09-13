import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ai_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pet.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.onOpenSettings});

  /// Lets an API key problem send the user straight to Settings.
  final VoidCallback? onOpenSettings;
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _messages = <Map<String, String>>[];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  /// Set when the last send failed, so the reason can be shown with a way out.
  AiException? _error;

  /// Kept so "Try again" can resend without retyping.
  String? _lastSent;

  static const _quickPrompts = [
    ('📊', 'How am I doing this week?', Palette.mint),
    ('🔍', 'Any patterns in my side effects?', Palette.lavender),
    ('🩺', 'What should I tell my doctor next visit?', Palette.coral),
    ('🍳', 'Easy high-protein meal ideas?', Palette.peach),
  ];

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _busy) return;
    setState(() {
      _messages.add({'role': 'user', 'content': text.trim()});
      _busy = true;
      _error = null;
    });
    _lastSent = text.trim();
    _ctrl.clear();
    _scrollToEnd();
    try {
      final reply = await AiService.ask(_messages);
      setState(() => _messages.add({'role': 'assistant', 'content': reply}));
    } catch (e) {
      // The question stays in the thread; the reason goes in its own card so
      // it never reads like the buddy answering.
      setState(() => _error = AiException.from(e));
    } finally {
      setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  /// Resends the last question after a failure.
  Future<void> _retry() async {
    final last = _lastSent;
    if (last == null || _busy) return;
    if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
      _messages.removeLast();
    }
    await _send(last);
  }

  Future<void> _scrollToEnd() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ValueListenableBuilder<PetSpecies>(
      valueListenable: petSpecies,
      builder: (context, _, __) => Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      SoftCard(
                        gradient: Palette.grape,
                        child: Row(
                          children: [
                            Text(petSpecies.value.icon,
                                style: const TextStyle(fontSize: 48)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Hi! I'm your buddy 👋",
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Ask me about your progress, side effects, meals, or what to bring up with your doctor.',
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: .95),
                                        height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const SectionTitle('Try asking', emoji: '💡'),
                      for (final q in _quickPrompts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SoftCard(
                            onTap: () => _send(q.$2),
                            color: q.$3.withValues(alpha: .14),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Text(q.$1,
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(q.$2,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700))),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 18, color: scheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _messages.length +
                        (_busy ? 1 : 0) +
                        (_error != null ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length && _error != null) {
                        return _AiErrorCard(
                          error: _error!,
                          onRetry: _retry,
                          onOpenSettings: widget.onOpenSettings,
                        );
                      }
                      if (i == _messages.length) {
                        return const _AssistantRow(child: _TypingDots());
                      }
                      final m = _messages[i];
                      final isUser = m['role'] == 'user';
                      if (isUser) {
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(
                                top: 6, bottom: 6, left: 48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            decoration: const BoxDecoration(
                              gradient: Palette.sunset,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(6),
                                bottomLeft: Radius.circular(20),
                                bottomRight: Radius.circular(20),
                              ),
                            ),
                            child: SelectableText(m['content']!,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35)),
                          ),
                        );
                      }
                      return _AssistantRow(
                        child: SelectableText(m['content']!,
                            style: const TextStyle(height: 1.4)),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Support and explanations only. Dose changes and medical decisions are for your doctor.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                decoration: BoxDecoration(
                  color: theme.inputDecorationTheme.fillColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Ask your buddy anything…',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: _send,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: _busy ? null : Palette.sunset,
                        color: _busy ? scheme.outlineVariant : null,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _busy ? null : () => _send(_ctrl.text),
                        icon: const Icon(Icons.arrow_upward_rounded,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantRow extends StatelessWidget {
  const _AssistantRow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6, right: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Palette.lavender.withValues(alpha: .18)),
            alignment: Alignment.center,
            child: Text(petSpecies.value.icon,
                style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .05),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .3)),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.translate(
                offset: Offset(
                    0,
                    -4 *
                        math.max(
                            0, math.sin((_c.value * 2 * math.pi) - i * 0.9))),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Palette.lavender),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Why the assistant could not answer, and the one thing to do about it.
///
/// Deliberately not a chat bubble: an outage or a missing key is the app
/// talking, not the companion.
class _AiErrorCard extends StatelessWidget {
  const _AiErrorCard({
    required this.error,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final AiException error;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  bool get _isKey =>
      error.kind == AiErrorKind.noKey || error.kind == AiErrorKind.invalidKey;

  Color get _color => switch (error.kind) {
        AiErrorKind.noKey || AiErrorKind.invalidKey => Palette.lavender,
        AiErrorKind.quota => Palette.peach,
        AiErrorKind.overloaded => Palette.sunshine,
        AiErrorKind.network || AiErrorKind.timeout => Palette.sky,
        _ => Palette.berry,
      };

  IconData get _icon => switch (error.kind) {
        AiErrorKind.noKey || AiErrorKind.invalidKey => Icons.key_rounded,
        AiErrorKind.quota => Icons.battery_2_bar_rounded,
        AiErrorKind.overloaded => Icons.hourglass_top_rounded,
        AiErrorKind.network || AiErrorKind.timeout => Icons.wifi_off_rounded,
        AiErrorKind.blocked => Icons.shield_outlined,
        _ => Icons.error_outline_rounded,
      };

  String get _title => switch (error.kind) {
        AiErrorKind.noKey => 'No API key yet',
        AiErrorKind.invalidKey => 'That key was not accepted',
        AiErrorKind.quota => 'Out of quota for today',
        AiErrorKind.overloaded => 'Gemini is busy',
        AiErrorKind.network => 'No connection',
        AiErrorKind.timeout => 'That took too long',
        AiErrorKind.blocked => 'Gemini declined that one',
        AiErrorKind.empty => 'Nothing came back',
        AiErrorKind.unknown => 'That did not work',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6, right: 24),
      child: SoftCard(
        color: _color.withValues(alpha: .14),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _color.withValues(alpha: .22)),
                  alignment: Alignment.center,
                  child: Icon(_icon, size: 18, color: _color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(error.message,
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: scheme.onSurface)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_isKey && onOpenSettings != null)
                  FilledButton.tonalIcon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.tune_rounded, size: 17),
                    label: const Text('Open Settings'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14)),
                  ),
                if (_isKey && onOpenSettings != null) const SizedBox(width: 8),
                if (error.retryable)
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Try again'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
