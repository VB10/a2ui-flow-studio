import 'dart:convert';
import 'dart:io';

import 'package:flow_core/flow_core.dart';
import 'package:http/http.dart' as http;

/// Result of an AI-assisted flow edit (Phase 6 / Level 2 Path A).
class AiEditResult {
  const AiEditResult({
    required this.flow,
    required this.summary,
    required this.usedRemoteLlm,
  });

  final FlowDefinition flow;
  final String summary;
  final bool usedRemoteLlm;
}

/// Level 2 (Path A): Edits a [FlowDefinition] from a natural language prompt
/// while preserving existing `field.key` and `step.id` identifiers, then
/// validates the resulting flow before returning.
///
/// If `GEMINI_API_KEY` is present in the environment, calls the Gemini API
/// with structured JSON output; otherwise (or if the API call fails), uses
/// a rich deterministic Turkish/English natural-language intent engine so demos
/// work reliably offline or during live broadcasts.
class AiFlowAssistant {
  AiFlowAssistant({
    http.Client? httpClient,
    String? geminiApiKey,
  })  : _httpClient = httpClient ?? http.Client(),
        _geminiApiKey =
            geminiApiKey ?? Platform.environment['GEMINI_API_KEY'];

  final http.Client _httpClient;
  final String? _geminiApiKey;

  Future<AiEditResult> applyPrompt({
    required FlowDefinition currentFlow,
    required String prompt,
  }) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      return AiEditResult(
        flow: currentFlow,
        summary: 'Boş komut gönderildi, değişiklik yapılmadı.',
        usedRemoteLlm: false,
      );
    }

    if (_geminiApiKey != null && _geminiApiKey.trim().isNotEmpty) {
      try {
        final remoteResult = await _callGemini(currentFlow, trimmedPrompt);
        if (remoteResult != null &&
            FlowValidator.validateFlow(remoteResult.flow).isEmpty) {
          return remoteResult;
        }
      } catch (e) {
        stderr.writeln('[AiFlowAssistant] Gemini call fallback: $e');
      }
    }

    return _applyLocalSmartIntent(currentFlow, trimmedPrompt);
  }

  Future<AiEditResult?> _callGemini(
    FlowDefinition currentFlow,
    String prompt,
  ) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
    );

    final systemInstruction = '''
Sen A2UI Flow Studio için bir FlowDefinition JSON düzenleyicisisin.
Kurallar:
1. Mevcut adımların `id` ve mevcut alanların `key` değerlerini ASLA değiştirme.
2. Yeni eklenen alanlara benzersiz snake_case `key` ver (örn: `age`, `department`, `phone`).
3. Alan tipleri sadece şunlardan biri olabilir: text, longText, email, number, date, singleChoice, multiChoice, checkbox, slider.
4. singleChoice ve multiChoice alanlarında en az 2 seçenek (`options: [{"value": "...", "label": "..."}]`) bulunmalıdır.
5. slider alanında `min` ve `max` (min < max) zorunludur.
6. Yanıt olarak SADECE geçerli bir JSON nesnesi döndür: {"summary": "yapılan değişikliğin kısa açıklaması", "flow": <FlowDefinition JSON>}.
''';

    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': systemInstruction},
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {
                    'text':
                        'Mevcut FlowDefinition JSON:\n${jsonEncode(currentFlow.toJson())}\n\nKullanıcı İsteği: $prompt',
                  },
                ],
              },
            ],
            'generationConfig': {
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = body['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final content =
        (candidates.first as Map<String, dynamic>)['content'] as Map?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) return null;
    final text = (parts.first as Map<String, dynamic>)['text'] as String?;
    if (text == null) return null;

    final parsed = jsonDecode(text) as Map<String, dynamic>;
    final flowJson = parsed['flow'] as Map<String, dynamic>?;
    if (flowJson == null) return null;

    return AiEditResult(
      flow: FlowDefinition.fromJson(flowJson),
      summary: (parsed['summary'] as String?) ?? 'AI ile akış güncellendi.',
      usedRemoteLlm: true,
    );
  }

  AiEditResult _applyLocalSmartIntent(
    FlowDefinition currentFlow,
    String prompt,
  ) {
    final lower = prompt.toLowerCase();
    var steps = List<FlowStep>.from(currentFlow.steps);
    final appliedChanges = <String>[];

    bool hasFieldKey(String key) =>
        steps.any((s) => s.fields.any((f) => f.key == key));

    String uniqueKey(String base) {
      if (!hasFieldKey(base)) return base;
      var i = 2;
      while (hasFieldKey('${base}_$i')) {
        i++;
      }
      return '${base}_$i';
    }

    // 1. "Öğrencilere bölümünü de sor" / student branch step
    if (lower.contains('öğrenci') ||
        lower.contains('bölüm') ||
        lower.contains('student') ||
        lower.contains('üniversite')) {
      const studentStepId = 'step_student_details';
      final existingIdx = steps.indexWhere((s) => s.id == studentStepId);

      final studentStep = FlowStep(
        id: studentStepId,
        title: 'Eğitim & Bölüm Bilgileri',
        description: 'Öğrenci ve araştırmacılar için akademik detaylar.',
        submitLabel: 'Tamamla',
        fields: [
          FlowField(
            key: uniqueKey('university_department'),
            type: FieldType.text,
            label: 'Bölümünüz / Çalışma Alanınız',
            placeholder: 'Örn. Bilgisayar Mühendisliği',
            required: true,
            minLength: 2,
          ),
          FlowField(
            key: uniqueKey('graduation_year'),
            type: FieldType.slider,
            label: 'Tahmini Mezuniyet Yılı',
            min: 2025,
            max: 2032,
            required: true,
          ),
        ],
        next: const StepNext(defaultStepId: null),
      );

      if (existingIdx == -1) {
        steps.add(studentStep);
      } else {
        steps[existingIdx] = studentStep;
      }

      // Wire branch rule on the step containing 'role' field (or step_role)
      final roleStepIdx = steps.indexWhere(
        (s) =>
            s.id == 'step_role' || s.fields.any((f) => f.key.contains('role')),
      );
      if (roleStepIdx != -1) {
        final roleStep = steps[roleStepIdx];
        final roleFieldKey = roleStep.fields
                .where((f) => f.key.contains('role'))
                .map((f) => f.key)
                .firstOrNull ??
            'role';
        final rules = List<BranchRule>.from(roleStep.next.rules);
        final alreadyHasRule = rules.any(
          (r) => r.fieldKey == roleFieldKey && r.equals == 'student',
        );
        if (!alreadyHasRule) {
          rules.add(
            BranchRule(
              fieldKey: roleFieldKey,
              equals: 'student',
              goToStepId: studentStepId,
            ),
          );
        }
        steps[roleStepIdx] = roleStep.copyWith(
          next: roleStep.next.copyWith(rules: rules),
        );
      }
      appliedChanges.add(
        'Öğrenciler için "Eğitim & Bölüm Bilgileri" adımı ve dallanma kuralı (role == student) eklendi.',
      );
    }

    // 2. "Yaş" / "Age" field (Slider or Number)
    if (lower.contains('yaş') || lower.contains('age')) {
      final useNumber = lower.contains('sayı') || lower.contains('number');
      final ageField = FlowField(
        key: uniqueKey('age'),
        type: useNumber ? FieldType.number : FieldType.slider,
        label: 'Yaşınızı girin',
        placeholder: useNumber ? 'Örn. 28' : null,
        required: true,
        min: 18,
        max: 80,
      );
      final firstStep = steps.first;
      steps[0] = firstStep.copyWith(
        fields: [...firstStep.fields, ageField],
      );
      appliedChanges.add(
        'İlk adıma "Yaşınızı girin" (${ageField.type.displayName}) alanı eklendi.',
      );
    }

    // 3. "Telefon" / "Phone"
    if (lower.contains('telefon') || lower.contains('phone')) {
      final phoneField = FlowField(
        key: uniqueKey('phone'),
        type: FieldType.text,
        label: 'Telefon Numarası',
        placeholder: '+90 5XX XXX XX XX',
        required: !lower.contains('opsiyonel'),
        minLength: 10,
      );
      final firstStep = steps.first;
      steps[0] = firstStep.copyWith(
        fields: [...firstStep.fields, phoneField],
      );
      appliedChanges.add('İlk adıma "Telefon Numarası" alanı eklendi.');
    }

    // 4. "Şirket" / "Company" / "Kurum"
    if (lower.contains('şirket') ||
        lower.contains('company') ||
        lower.contains('kurum')) {
      final companyField = FlowField(
        key: uniqueKey('company'),
        type: FieldType.text,
        label: 'Şirket / Kurum Adı',
        placeholder: 'Örn. Acme Corp',
        required: !lower.contains('opsiyonel'),
      );
      final firstStep = steps.first;
      steps[0] = firstStep.copyWith(
        fields: [...firstStep.fields, companyField],
      );
      appliedChanges.add('İlk adıma "Şirket / Kurum Adı" alanı eklendi.');
    }

    // 5. "Deneyim" / "Tecrübe" / "Experience"
    if (lower.contains('deneyim') ||
        lower.contains('tecrübe') ||
        lower.contains('experience')) {
      final expField = FlowField(
        key: uniqueKey('experience_years'),
        type: FieldType.slider,
        label: 'Deneyim Yılı',
        required: true,
        min: 0,
        max: 25,
      );
      final targetIdx = steps.length > 1 ? 1 : 0;
      final step = steps[targetIdx];
      steps[targetIdx] = step.copyWith(
        fields: [...step.fields, expField],
      );
      appliedChanges.add('"${step.title}" adımına "Deneyim Yılı" slider alanı eklendi.');
    }

    // 6. "KVKK" / "Koşul" / "Onay" / "Terms" checkbox
    if (lower.contains('kvkk') ||
        lower.contains('koşul') ||
        lower.contains('onay') ||
        lower.contains('terms')) {
      final kvkkField = FlowField(
        key: uniqueKey('kvkk_consent'),
        type: FieldType.checkbox,
        label: 'KVKK ve Kullanım Koşullarını kabul ediyorum',
        required: true,
      );
      final firstStep = steps.first;
      steps[0] = firstStep.copyWith(
        fields: [...firstStep.fields, kvkkField],
      );
      appliedChanges.add('Zorunlu "KVKK ve Kullanım Koşulları" onay kutusu eklendi.');
    }

    // 7. "Doğum tarihi" / "Tarih" / "Date"
    if (lower.contains('doğum') ||
        lower.contains('tarih') ||
        lower.contains('date')) {
      final dateField = FlowField(
        key: uniqueKey('birth_date'),
        type: FieldType.date,
        label: 'Doğum Tarihi',
        required: true,
      );
      final firstStep = steps.first;
      steps[0] = firstStep.copyWith(
        fields: [...firstStep.fields, dateField],
      );
      appliedChanges.add('İlk adıma "Doğum Tarihi" alanı eklendi.');
    }

    // 8. Generic fallback if no specific keyword matched
    if (appliedChanges.isEmpty) {
      final customField = FlowField(
        key: uniqueKey('custom_note'),
        type: FieldType.longText,
        label: prompt.length > 48 ? '${prompt.substring(0, 48)}...' : prompt,
        placeholder: 'Yanıtınızı buraya yazın...',
        required: false,
      );
      final lastIdx = steps.length - 1;
      final lastStep = steps[lastIdx];
      steps[lastIdx] = lastStep.copyWith(
        fields: [...lastStep.fields, customField],
      );
      appliedChanges.add(
        '"${lastStep.title}" adımına "${customField.label}" alanı eklendi.',
      );
    }

    final updatedFlow = currentFlow.copyWith(steps: steps);
    return AiEditResult(
      flow: updatedFlow,
      summary: appliedChanges.join(' '),
      usedRemoteLlm: false,
    );
  }
}

