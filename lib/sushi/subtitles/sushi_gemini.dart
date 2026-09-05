import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;

import 'package:fladder/sushi/sushi_http.dart';
import 'package:fladder/sushi/subtitles/sushi_srt.dart';

/// New API keys cannot call Gemini 2.x (`no longer available to new users`).
/// Live-probed 2026-09-04: 3.1-flash-lite + 3.5-flash-lite + flash-lite-latest
/// accept thinkingLevel=minimal. 3.8-flash / flash-latest return HTTP 400.
const sushiGeminiModels = [
  'gemini-3.1-flash-lite',
  'gemini-3.5-flash-lite',
  'gemini-flash-lite-latest',
  'gemini-3.5-flash',
];
const _timeout = Duration(seconds: 60);

class SushiGeminiException implements Exception {
  SushiGeminiException(this.message, {this.suggestedModel});
  final String message;
  final String? suggestedModel;
  @override
  String toString() => 'SushiGeminiException: $message';
}

/// Thin REST client for the user-owned Gemini key (doc 15 §12). No Firebase, no deprecated SDK.
class SushiGeminiClient {
  SushiGeminiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  String? _resolvedModel;

  Future<String> translateCuesToPersian(
    List<SushiSrtCue> cues,
    String apiKey, {
    int concurrency = 1,
  }) async {
    if (cues.isEmpty) return '';
    final batches = sushiBatchSrtCues(cues);
    if (batches.isEmpty) return '';
    final out = List<List<SushiSrtCue>?>.filled(batches.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= batches.length) return;
        final batch = batches[i];
        log(
          'sushi_gemini_batch ${i + 1}/${batches.length} cues=${batch.length}',
          name: 'sushi.subs',
        );
        var reply = '';
        try {
          reply = await generateContent(
            apiKey: apiKey,
            prompt: _prompt(sushiNumberedCuePayload(batch)),
          );
        } on SushiGeminiException catch (e) {
          if (!e.message.contains('HTTP 429')) rethrow;
          await Future<void>.delayed(const Duration(seconds: 2));
          reply = await generateContent(
            apiKey: apiKey,
            prompt: _prompt(sushiNumberedCuePayload(batch)),
          );
        }
        out[i] = sushiApplyNumberedTranslations(batch, reply);
      }
    }

    final n = concurrency.clamp(1, batches.length);
    await Future.wait(List.generate(n, (_) => worker()));
    return sushiBuildSrt([for (final b in out) ...b!]);
  }

  Future<String> generateContent({required String apiKey, required String prompt}) async {
    final key = apiKey.trim();
    if (key.isEmpty) throw SushiGeminiException('empty api key');
    final queue = <String>[
      if (_resolvedModel != null) _resolvedModel!,
      ...sushiGeminiModels,
    ];
    final tried = <String>{};
    SushiGeminiException? last;
    while (queue.isNotEmpty) {
      final model = queue.removeAt(0);
      if (!tried.add(model)) continue;
      try {
        final text = await _postGenerate(model: model, apiKey: key, prompt: prompt);
        _resolvedModel = model;
        return text;
      } on SushiGeminiException catch (e) {
        last = e;
        if (e.message.startsWith('HTTP 400')) continue;
        if (!e.message.startsWith('HTTP 404')) rethrow;
        final next = e.suggestedModel ?? sushiGeminiSuggestedModel(e.message);
        if (next != null && !tried.contains(next)) queue.add(next);
      }
    }
    throw last ?? SushiGeminiException('HTTP 404');
  }

  Future<String> _postGenerate({
    required String model,
    required String apiKey,
    required String prompt,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    ).replace(queryParameters: {'key': apiKey});
    sushiHttpAssertAllowed(uri);
    final resp = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': kSushiHttpUserAgent,
          },
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.2,
              'thinkingConfig': {
                'thinkingLevel': 'minimal',
              },
            },
          }),
        )
        .timeout(_timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw SushiGeminiException(
        'HTTP ${resp.statusCode} model=$model${_bodyHint(resp.body)}',
        suggestedModel: sushiGeminiSuggestedModel(resp.body),
      );
    }
    final text = sushiGeminiExtractText(resp.body);
    if (text.isEmpty) throw SushiGeminiException('empty model reply model=$model');
    return text;
  }

  void close() => _client.close();
}

String sushiGeminiExtractText(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return '';
  final candidates = decoded['candidates'];
  if (candidates is! List || candidates.isEmpty) return '';
  final first = candidates.first;
  if (first is! Map) return '';
  final content = first['content'];
  if (content is! Map) return '';
  final parts = content['parts'];
  if (parts is! List) return '';
  final buf = StringBuffer();
  for (final p in parts) {
    if (p is Map && p['text'] is String) buf.write(p['text'] as String);
  }
  return buf.toString().trim();
}

/// Google 404s for retired models include `Please update your code to use models/<id>`.
String? sushiGeminiSuggestedModel(String body) {
  return RegExp(
    r'use models/(gemini-[a-z0-9.\-]+)',
    caseSensitive: false,
  ).firstMatch(body)?.group(1);
}

String _bodyHint(String body) {
  final t = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return '';
  return ' ${t.length > 600 ? t.substring(0, 600) : t}';
}

bool sushiLooksLikeGeminiKey(String raw) {
  final t = raw.trim();
  if (t.length < 30 || t.length > 80) return false;
  if (!t.startsWith('AIza') && !t.startsWith('AQ.')) return false;
  return !t.contains(RegExp(r'\s'));
}

String _prompt(String numbered) =>
    'Translate each numbered subtitle line into Persian (Farsi). '
    'Keep the same numbering (`1. …`). Preserve names, numbers, and on-screen text in Latin '
    'when they are proper nouns. Do not add commentary. Do not merge or drop lines.\n\n'
    '$numbered';
