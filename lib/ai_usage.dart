import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'db.dart';

/// What the assistant has cost so far, counted from the token numbers Gemini
/// returns with every answer rather than estimated.
///
/// One row per calendar month in the settings table, so the figure survives
/// restarts, travels with a Drive backup, and can be read in Settings without
/// a cable and a log. Recording never throws: a failed count must not turn
/// into a failed answer.
class AiUsage {
  /// Google's published paid-tier price for gemini-3.8-flash, USD per million
  /// tokens. Output includes thinking tokens. The schedule doubles both on
  /// 1 January 2027; update here when Google changes it again.
  static double inputUsdPerMillion(DateTime at) => at.year >= 2027 ? 1.50 : 0.75;
  static double outputUsdPerMillion(DateTime at) =>
      at.year >= 2027 ? 7.50 : 3.75;

  static double estimateUsd({
    required int inputTokens,
    required int outputTokens,
    required DateTime at,
  }) =>
      inputTokens / 1e6 * inputUsdPerMillion(at) +
      outputTokens / 1e6 * outputUsdPerMillion(at);

  /// Settings key for the month [d] falls in.
  static String keyFor(DateTime d) =>
      'ai_usage_${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Billable counts from a generateContent response, or null when the reply
  /// carried none. Thinking tokens are billed as output, so they are added in.
  static ({int input, int output})? countsFrom(Map<String, dynamic> data) {
    final u = data['usageMetadata'];
    if (u is! Map) return null;
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final input = n(u['promptTokenCount']);
    final output = n(u['candidatesTokenCount']) + n(u['thoughtsTokenCount']);
    if (input == 0 && output == 0) return null;
    return (input: input, output: output);
  }

  /// Adds one answer's tokens to the current month.
  static Future<void> record({
    required int inputTokens,
    required int outputTokens,
    DateTime? at,
  }) async {
    try {
      final now = at ?? DateTime.now();
      final cur = await month(now);
      final next = UsageMonth(
        at: now,
        requests: cur.requests + 1,
        inputTokens: cur.inputTokens + inputTokens,
        outputTokens: cur.outputTokens + outputTokens,
      );
      await AppDb.instance.setSetting(keyFor(now), jsonEncode(next.toMap()));
    } catch (e) {
      debugPrint('Usage record failed: $e');
    }
  }

  /// Totals for the month [d] falls in; zeros when nothing was recorded.
  static Future<UsageMonth> month(DateTime d) async {
    final raw = await AppDb.instance.getSetting(keyFor(d));
    if (raw == null) return UsageMonth.empty(d);
    try {
      return UsageMonth.fromMap(jsonDecode(raw) as Map<String, dynamic>, d);
    } catch (_) {
      return UsageMonth.empty(d);
    }
  }
}

/// One month of assistant usage.
class UsageMonth {
  const UsageMonth({
    required this.at,
    required this.requests,
    required this.inputTokens,
    required this.outputTokens,
  });

  UsageMonth.empty(this.at)
      : requests = 0,
        inputTokens = 0,
        outputTokens = 0;

  /// Any date inside the month; decides the price schedule.
  final DateTime at;
  final int requests;
  final int inputTokens;
  final int outputTokens;

  double get usd => AiUsage.estimateUsd(
      inputTokens: inputTokens, outputTokens: outputTokens, at: at);

  Map<String, Object?> toMap() => {
        'requests': requests,
        'in': inputTokens,
        'out': outputTokens,
      };

  static UsageMonth fromMap(Map<String, dynamic> m, DateTime at) => UsageMonth(
        at: at,
        requests: (m['requests'] as num?)?.toInt() ?? 0,
        inputTokens: (m['in'] as num?)?.toInt() ?? 0,
        outputTokens: (m['out'] as num?)?.toInt() ?? 0,
      );
}
