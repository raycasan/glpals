import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'db.dart';

/// Why a call to the assistant did not work.
enum AiErrorKind {
  noKey,
  invalidKey,
  quota,
  overloaded,
  network,
  timeout,
  blocked,
  empty,
  unknown,
}

/// An assistant failure with wording meant for the person reading it.
///
/// Every screen that calls the model shows [message] as-is, so the same cause
/// reads the same way everywhere, and [detail] keeps the raw text for logs.
class AiException implements Exception {
  const AiException(this.kind, this.message,
      {this.detail, this.retryable = false});

  final AiErrorKind kind;

  /// One or two plain sentences, ending with what to do next.
  final String message;
  final String? detail;

  /// True when trying the same request again could reasonably work.
  final bool retryable;

  /// Label for the action button, when there is a sensible action.
  String? get actionLabel => switch (kind) {
        AiErrorKind.noKey || AiErrorKind.invalidKey => 'Open Settings',
        _ => retryable ? 'Try again' : null,
      };

  String get emoji => switch (kind) {
        AiErrorKind.noKey || AiErrorKind.invalidKey => 'KEY',
        AiErrorKind.quota => 'QUOTA',
        AiErrorKind.overloaded => 'BUSY',
        AiErrorKind.network || AiErrorKind.timeout => 'NET',
        AiErrorKind.blocked => 'BLOCKED',
        _ => 'ERR',
      };

  @override
  String toString() => message;

  /// Normalises anything thrown on the way to the model.
  static AiException from(Object e) {
    if (e is AiException) return e;
    if (e is TimeoutException) {
      return const AiException(
        AiErrorKind.timeout,
        'The assistant took too long to answer. That is usually a slow '
        'connection. Try again.',
        retryable: true,
      );
    }
    if (e is SocketException || e is HttpException) {
      return AiException(
        AiErrorKind.network,
        'No connection to the assistant. Check your network and try again. '
        'Everything else in the app works offline.',
        detail: e.toString(),
        retryable: true,
      );
    }
    return AiException(AiErrorKind.unknown,
        'The assistant could not answer that one. Try again in a moment.',
        detail: e.toString(), retryable: true);
  }

  /// Builds the right error from an HTTP failure.
  static AiException fromStatus(int status, String body) {
    final b = body.toLowerCase();
    if (status == 429 || b.contains('resource_exhausted')) {
      return AiException(
        AiErrorKind.quota,
        'The free Gemini quota for today is used up. It resets after midnight '
        'Pacific time, or you can raise the limit in Google AI Studio.',
        detail: body,
      );
    }
    if ((status == 400 && b.contains('api_key_invalid')) ||
        status == 401 ||
        b.contains('api key not valid')) {
      return AiException(
        AiErrorKind.invalidKey,
        'Google did not accept that API key. Check it in Settings, or make a '
        'new one in Google AI Studio.',
        detail: body,
      );
    }
    if (status == 403) {
      return AiException(
        AiErrorKind.invalidKey,
        'That key is not allowed to use this model. Check in Google AI Studio '
        'that the Generative Language API is enabled for it.',
        detail: body,
      );
    }
    if (status == 503 || status == 500 || b.contains('overloaded')) {
      return AiException(
        AiErrorKind.overloaded,
        'Gemini is busy right now. This one is on Google, not you. Try again '
        'in a minute.',
        detail: body,
        retryable: true,
      );
    }
    if (status == 404) {
      return AiException(
        AiErrorKind.unknown,
        'That model is not available to this key. It may have been retired.',
        detail: body,
      );
    }
    return AiException(
      AiErrorKind.unknown,
      'The assistant returned an error ($status). Try again in a moment.',
      detail: body,
      retryable: true,
    );
  }
}

/// Thin client for the Google Gemini API (generateContent). The API key is a
/// Google AI Studio key, stored in the device keychain/keystore.
class AiService {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'gemini_api_key';

  /// Tried in order; the next one is used when a model is overloaded (503)
  /// or rate limited (429).
  static const models = ['gemini-3.8-flash', 'gemini-3.7-flash'];
  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static Future<String?> getKey() => _storage.read(key: _keyName);
  static Future<void> setKey(String k) =>
      _storage.write(key: _keyName, value: k.trim());

  static const _systemPrompt = '''
You are a supportive companion inside a personal tracking app for someone taking tirzepatide (a GLP-1/GIP medication) for weight management. You are talking to the patient herself.

You can:
- Explain in plain language what is normal on this medication (appetite changes, common side effects, why protein, fiber, and water matter, food that tends to sit better).
- Read the tracking data you are given and point out patterns: side effects clustering after shot day, hydration or protein dipping, weight trends. Be specific and reference actual numbers and dates.
- Suggest practical, low-risk things: meal ideas, hydration habits, gentle activity, what to write down for her next appointment.
- Encourage her warmly without being saccharine.

You must not:
- Recommend starting, stopping, skipping, splitting, or changing a dose or the dose schedule. Dose decisions belong to her prescribing doctor. If asked, explain why and suggest what to bring up with the doctor.
- Diagnose. If she describes severe or persistent symptoms (severe abdominal pain, repeated vomiting, inability to keep fluids down, signs of dehydration, yellowing skin, severe allergic reaction), tell her clearly to contact her doctor or urgent care now.
- Give specific calorie targets or push restriction. Keep the focus on adequate protein, fiber, and fluids.

Keep answers short: this is read on a phone. Use plain sentences, no headers. Lists only when listing things.
''';

  /// Builds a compact summary of recent logs so the model can reason on real data.
  static Future<String> buildContext() async {
    final db = AppDb.instance;
    final shots = await db.shots(limit: 8);
    final logs = await db.logs(days: 21);
    final df = DateFormat('MMM d');
    final b = StringBuffer();
    b.writeln(
        'Today: ${DateFormat('yyyy-MM-dd (EEEE)').format(DateTime.now())}');
    b.writeln('Recent shots (newest first):');
    if (shots.isEmpty) b.writeln('  none logged yet');
    for (final s in shots) {
      b.writeln('  ${df.format(s.takenAt)} ${s.doseMg} mg at ${s.site}'
          '${s.note.isNotEmpty ? ' - ${s.note}' : ''}');
    }
    b.writeln('Daily check-ins (last ${logs.length} days):');
    for (final l in logs) {
      final se = l.sideEffects.entries
          .where((e) => e.value > 0)
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      b.writeln('  ${l.day}: weight=${l.weightKg?.toStringAsFixed(1) ?? '-'}kg '
          'water=${l.waterMl}ml protein=${l.proteinG}g'
          '${se.isNotEmpty ? ' side effects: $se' : ''}'
          '${l.note.isNotEmpty ? ' note: ${l.note}' : ''}');
    }
    final meals = await db.meals(limit: 30);
    b.writeln('Recent meals (newest first):');
    if (meals.isEmpty) b.writeln('  none logged yet');
    for (final m in meals) {
      b.writeln(
          '  ${DateFormat('MMM d HH:mm').format(m.eatenAt)} ${m.description}: '
          '${m.proteinG}g protein, ${m.fiberG}g fiber, ~${m.calories} kcal');
    }
    return b.toString();
  }

  /// One generateContent call. [contents] follow the Gemini shape:
  /// {role: user|model, parts: [{text} | {inlineData}]}.
  static Future<String> _call({
    required String system,
    required List<Map<String, dynamic>> contents,
    int maxTokens = 8192,
    Map<String, dynamic>? responseSchema,
    String? thinkingLevel,
  }) async {
    final key = await getKey();
    if (key == null || key.isEmpty) {
      throw const AiException(
        AiErrorKind.noKey,
        'Your buddy needs a Gemini API key before it can answer. Add one in '
        'Settings; it is free from Google AI Studio.',
      );
    }
    // Gemini counts its thinking tokens against maxOutputTokens, so the cap
    // stays generous and the level is lowered for quick structured answers.
    final generation = <String, dynamic>{'maxOutputTokens': maxTokens};
    if (thinkingLevel != null) {
      generation['thinkingConfig'] = {'thinkingLevel': thinkingLevel};
    }
    if (responseSchema != null) {
      generation['responseMimeType'] = 'application/json';
      generation['responseSchema'] = responseSchema;
    }
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': contents,
      'generationConfig': generation,
    });
    http.Response? res;
    for (final model in models) {
      try {
        res = await http
            .post(
              Uri.parse('$_base/$model:generateContent'),
              headers: {
                'content-type': 'application/json',
                'x-goog-api-key': key,
              },
              body: body,
            )
            .timeout(const Duration(seconds: 90));
      } catch (e) {
        throw AiException.from(e);
      }
      // A busy or rate-limited model is worth retrying on the next one.
      if (res.statusCode != 503 && res.statusCode != 429) break;
    }
    res!;
    if (res.statusCode != 200) {
      throw AiException.fromStatus(res.statusCode, res.body);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = (data['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      final reason = (data['promptFeedback'] as Map?)?['blockReason'];
      if (reason != null) {
        throw AiException(
          AiErrorKind.blocked,
          'Gemini declined to answer that one, its safety filter flagged the '
          'request. Rewording the question usually helps.',
          detail: '$reason',
        );
      }
      throw const AiException(
        AiErrorKind.empty,
        'The assistant came back empty. Try asking again, or make the question '
        'a little shorter.',
        retryable: true,
      );
    }
    final first = candidates.first as Map<String, dynamic>;
    final parts = ((first['content'] as Map?)?['parts'] as List?) ?? const [];
    final text = parts
        .cast<Map<String, dynamic>>()
        .where((p) => p['text'] != null && p['thought'] != true)
        .map((p) => p['text'] as String)
        .join('\n')
        .trim();
    if (text.isEmpty) {
      final finish = '${first['finishReason'] ?? 'unknown'}'.toUpperCase();
      final safety = finish.contains('SAFETY');
      throw AiException(
        safety ? AiErrorKind.blocked : AiErrorKind.empty,
        safety
            ? 'Gemini stopped partway on its safety filter. Try rewording the '
                'question.'
            : finish.contains('MAX_TOKENS')
                ? 'The answer ran past the length limit before any text came '
                    'back. Try a narrower question.'
                : 'The assistant came back empty. Try again in a moment.',
        detail: finish,
        retryable: !safety,
      );
    }
    return text;
  }

  /// [history] is alternating user/assistant turns from this chat session.
  static Future<String> ask(List<Map<String, String>> history) async {
    final context = await buildContext();
    return _call(
      system: '$_systemPrompt\n\n<tracking_data>\n$context</tracking_data>',
      contents: [
        for (final m in history)
          {
            'role': m['role'] == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': m['content'] ?? ''}
            ],
          },
      ],
    );
  }

  static const _mealPrompt = '''
You estimate the nutrition of one meal for a personal food log. Return ONLY a JSON object, no prose, no markdown fences:
{"description": "short name of the meal", "protein_g": int, "fiber_g": int, "calories": int, "confidence": "low"|"medium"|"high", "note": "one short sentence on what drove the estimate"}

Rules:
- If the user lists ingredients with amounts, treat those as ground truth and compute from them; use the photo only to fill gaps (cooking method, items they did not list). Confidence should then be high.
- If ingredients are listed without amounts, use the photo to judge portions. Confidence medium.
- If only a photo is given, estimate a typical single serving as plated. Confidence low or medium.
- Assume Filipino home cooking and portions when the food looks like it (rice, ulam, sinigang, adobo, pancit, etc.).
- Round to whole numbers. Never return ranges.
''';

  static const _mealSchema = <String, dynamic>{
    'type': 'OBJECT',
    'properties': {
      'description': {'type': 'STRING'},
      'protein_g': {'type': 'INTEGER'},
      'fiber_g': {'type': 'INTEGER'},
      'calories': {'type': 'INTEGER'},
      'confidence': {
        'type': 'STRING',
        'enum': ['low', 'medium', 'high']
      },
      'note': {'type': 'STRING'},
    },
    'required': [
      'description',
      'protein_g',
      'fiber_g',
      'calories',
      'confidence',
      'note'
    ],
  };

  static const _planPrompt = '''
You are setting up a personal GLP-1 tracking app for someone who has just told you what they are taking and a little about themselves. Return ONLY a JSON object, no prose, no markdown fences.

Produce:
- protein_g: a daily protein target in grams. Roughly 1.2-1.6 g per kg of current body weight, rounded to the nearest 5. Protein protects muscle while appetite is low, which is the single most useful number in this app.
- water_ml: a daily fluid target in millilitres, roughly 30-35 ml per kg, rounded to the nearest 250.
- fiber_g: a daily fibre target in grams, usually 25-30.
- welcome: one warm sentence, max 20 words, addressed to them.
- tips: exactly 4 short, concrete, low-risk tips for their first weeks on this specific medication. Each under 110 characters. Cover what usually helps early: eating pattern, protein, fluids, and what to watch for.
- watch_for: one sentence naming the symptoms that mean they should call their doctor rather than wait.

Rules:
- Never suggest starting, stopping, changing, splitting or skipping a dose, and never comment on whether their dose is right. That belongs to their prescriber.
- No calorie targets and nothing that reads as pressure to restrict.
- Plain language, no headers, no emoji in tips.
''';

  static const _planSchema = <String, dynamic>{
    'type': 'OBJECT',
    'properties': {
      'protein_g': {'type': 'INTEGER'},
      'water_ml': {'type': 'INTEGER'},
      'fiber_g': {'type': 'INTEGER'},
      'welcome': {'type': 'STRING'},
      'tips': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'}
      },
      'watch_for': {'type': 'STRING'},
    },
    'required': [
      'protein_g',
      'water_ml',
      'fiber_g',
      'welcome',
      'tips',
      'watch_for'
    ],
  };

  /// Builds the starting plan shown at the end of onboarding: daily targets
  /// plus a few tips written for the product the user is actually on.
  static Future<Map<String, dynamic>> onboardingPlan({
    required String product,
    required String molecule,
    required String schedule,
    required double doseMg,
    double? weightKg,
    double? goalWeightKg,
    double? heightCm,
    String? startedOn,
  }) async {
    final b = StringBuffer()
      ..writeln('Medication: $product ($molecule), $schedule.')
      ..writeln('Current dose: $doseMg mg.');
    if (startedOn != null) b.writeln('Started around: $startedOn.');
    if (weightKg != null) b.writeln('Current weight: $weightKg kg.');
    if (goalWeightKg != null) b.writeln('Goal weight: $goalWeightKg kg.');
    if (heightCm != null) b.writeln('Height: $heightCm cm.');
    b.writeln('They cook and eat mostly Filipino food.');
    final raw = await _call(
      system: _planPrompt,
      contents: [
        {
          'role': 'user',
          'parts': [
            {'text': b.toString()}
          ]
        }
      ],
      maxTokens: 4096,
      responseSchema: _planSchema,
      thinkingLevel: 'low',
    );
    final clean = raw.replaceAll(RegExp(r'```json|```'), '').trim();
    return jsonDecode(clean) as Map<String, dynamic>;
  }

  /// Nutrition estimate from a photo and/or typed ingredients. At least one must be given.
  static Future<Map<String, dynamic>> analyzeMeal({
    Uint8List? imageBytes,
    String mimeType = 'image/jpeg',
    String ingredients = '',
  }) async {
    final parts = <Map<String, dynamic>>[];
    if (imageBytes != null) {
      parts.add({
        'inlineData': {'mimeType': mimeType, 'data': base64Encode(imageBytes)},
      });
    }
    parts.add({
      'text': ingredients.trim().isEmpty
          ? 'Estimate this meal from the photo.'
          : 'Ingredients and amounts I used:\n${ingredients.trim()}\n'
              '${imageBytes != null ? 'A photo of the plate is attached.' : 'No photo.'}',
    });
    final raw = await _call(
      system: _mealPrompt,
      contents: [
        {'role': 'user', 'parts': parts}
      ],
      maxTokens: 4096,
      responseSchema: _mealSchema,
      thinkingLevel: 'low',
    );
    final clean = raw.replaceAll(RegExp(r'```json|```'), '').trim();
    return jsonDecode(clean) as Map<String, dynamic>;
  }
}
