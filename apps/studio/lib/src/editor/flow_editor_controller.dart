import 'dart:async';

import 'package:flow_core/flow_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/studio_api_client.dart';

const String kStudioServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://localhost:8080',
);

final studioApiClientProvider = Provider<StudioApiClient>((ref) {
  final client = HttpStudioApiClient(baseUrl: kStudioServerUrl);
  ref.onDispose(client.dispose);
  return client;
});

/// Immutable state for the Studio Web Editor.
class FlowEditorState {
  const FlowEditorState({
    required this.snapshot,
    this.selectedStepId,
    this.previewMessages = const [],
    this.isLoading = false,
    this.isSavingDraft = false,
    this.isPublishing = false,
    this.isAiBusy = false,
    this.errorMessage,
    this.statusMessage,
  });

  final FlowSnapshot snapshot;
  final String? selectedStepId;
  final List<Map<String, Object?>> previewMessages;
  final bool isLoading;
  final bool isSavingDraft;
  final bool isPublishing;
  final bool isAiBusy;
  final String? errorMessage;
  final String? statusMessage;

  FlowDefinition get draft => snapshot.draft;
  int get publishedVersion => snapshot.publishedVersion;
  bool get hasUnpublishedChanges => snapshot.hasUnpublishedChanges;

  FlowStep? get selectedStep {
    if (draft.steps.isEmpty) return null;
    if (selectedStepId != null) {
      final found = draft.stepById(selectedStepId!);
      if (found != null) return found;
    }
    return draft.steps.first;
  }

  List<FlowValidationIssue> get validationIssues =>
      FlowValidator.validateFlow(draft);

  bool get canPublish => validationIssues.isEmpty && !isPublishing;

  FlowEditorState copyWith({
    FlowSnapshot? snapshot,
    String? selectedStepId,
    List<Map<String, Object?>>? previewMessages,
    bool? isLoading,
    bool? isSavingDraft,
    bool? isPublishing,
    bool? isAiBusy,
    String? errorMessage,
    bool clearError = false,
    String? statusMessage,
    bool clearStatus = false,
  }) =>
      FlowEditorState(
        snapshot: snapshot ?? this.snapshot,
        selectedStepId: selectedStepId ?? this.selectedStepId,
        previewMessages: previewMessages ?? this.previewMessages,
        isLoading: isLoading ?? this.isLoading,
        isSavingDraft: isSavingDraft ?? this.isSavingDraft,
        isPublishing: isPublishing ?? this.isPublishing,
        isAiBusy: isAiBusy ?? this.isAiBusy,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        statusMessage:
            clearStatus ? null : (statusMessage ?? this.statusMessage),
      );
}

/// Riverpod Notifier managing the Studio editor state, debounced draft saving,
/// step/field CRUD, branch rules, live A2UI JSON preview, and AI prompt editing.
class FlowEditorController extends AutoDisposeNotifier<FlowEditorState> {
  late StudioApiClient _api;
  Timer? _debounceTimer;
  int _idCounter = 100;

  Duration debounceDuration = const Duration(milliseconds: 350);

  @override
  FlowEditorState build() {
    _api = ref.watch(studioApiClientProvider);
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });

    final initialTemplate = createDefaultFlowTemplate();
    Future.microtask(loadInitialFlow);
    return FlowEditorState(
      snapshot: FlowSnapshot(
        draft: initialTemplate,
        published: initialTemplate,
        publishedVersion: 1,
      ),
      selectedStepId: initialTemplate.steps.first.id,
      isLoading: true,
    );
  }

  Future<void> loadInitialFlow() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final snapshot = await _api.getFlow();
      final stepId = snapshot.draft.steps.firstOrNull?.id;
      state = state.copyWith(
        snapshot: snapshot,
        selectedStepId: stepId,
        isLoading: false,
      );
      await refreshPreview();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sunucudan akış yüklenemedi: $e',
      );
    }
  }

  void selectStep(String stepId) {
    state = state.copyWith(selectedStepId: stepId);
    unawaited(refreshPreview());
  }

  void updateFlowTitle(String newTitle) {
    _applyDraftMutation(state.draft.copyWith(title: newTitle));
  }

  // ---------------------------------------------------------------------------
  // Step operations
  // ---------------------------------------------------------------------------

  void addStep({String? title}) {
    final index = state.draft.steps.length + 1;
    final stepId = 'step_${++_idCounter}';
    final newStep = FlowStep(
      id: stepId,
      title: title ?? 'Yeni Adım $index',
      description: 'Bu adım için açıklama girin.',
      submitLabel: 'Devam Et',
      fields: [
        FlowField(
          key: 'field_${++_idCounter}',
          type: FieldType.text,
          label: 'Yeni Alan',
          required: true,
        ),
      ],
    );

    final steps = List<FlowStep>.from(state.draft.steps);
    if (steps.isNotEmpty) {
      final prevLast = steps.last;
      if (prevLast.next.defaultStepId == null) {
        steps[steps.length - 1] = prevLast.copyWith(
          next: prevLast.next.copyWith(defaultStepId: stepId),
        );
      }
    }
    steps.add(newStep);

    state = state.copyWith(selectedStepId: stepId);
    _applyDraftMutation(state.draft.copyWith(steps: steps));
  }

  void deleteStep(String stepId) {
    final steps = state.draft.steps.where((s) => s.id != stepId).map((s) {
      final cleanedDefault =
          s.next.defaultStepId == stepId ? null : s.next.defaultStepId;
      final cleanedRules =
          s.next.rules.where((r) => r.goToStepId != stepId).toList();
      return s.copyWith(
        next: StepNext(
          defaultStepId: cleanedDefault,
          rules: cleanedRules,
        ),
      );
    }).toList();

    final nextSelected = state.selectedStepId == stepId
        ? steps.firstOrNull?.id
        : state.selectedStepId;

    state = state.copyWith(selectedStepId: nextSelected);
    _applyDraftMutation(state.draft.copyWith(steps: steps));
  }

  void moveStep(String stepId, int delta) {
    final steps = List<FlowStep>.from(state.draft.steps);
    final idx = steps.indexWhere((s) => s.id == stepId);
    if (idx == -1) return;
    final targetIdx = idx + delta;
    if (targetIdx < 0 || targetIdx >= steps.length) return;

    final item = steps.removeAt(idx);
    steps.insert(targetIdx, item);
    _applyDraftMutation(state.draft.copyWith(steps: steps));
  }

  void updateSelectedStep({
    String? title,
    String? description,
    String? submitLabel,
    StepNext? next,
  }) {
    final current = state.selectedStep;
    if (current == null) return;

    final updated = current.copyWith(
      title: title,
      description: description,
      submitLabel: submitLabel,
      next: next,
    );
    _replaceStep(updated);
  }

  // ---------------------------------------------------------------------------
  // Field operations
  // ---------------------------------------------------------------------------

  void addFieldToSelectedStep(FlowField field) {
    final current = state.selectedStep;
    if (current == null) return;

    final updated = current.copyWith(
      fields: [...current.fields, field],
    );
    _replaceStep(updated);
  }

  void updateFieldInSelectedStep(String fieldKey, FlowField updatedField) {
    final current = state.selectedStep;
    if (current == null) return;

    // Preserve original immutable field.key
    final enforced = updatedField.copyWith(key: fieldKey);
    final fields = [
      for (final f in current.fields)
        if (f.key == fieldKey) enforced else f,
    ];
    _replaceStep(current.copyWith(fields: fields));
  }

  void deleteFieldFromSelectedStep(String fieldKey) {
    final current = state.selectedStep;
    if (current == null) return;

    final fields = current.fields.where((f) => f.key != fieldKey).toList();
    _replaceStep(current.copyWith(fields: fields));
  }

  void moveFieldInSelectedStep(String fieldKey, int delta) {
    final current = state.selectedStep;
    if (current == null) return;

    final fields = List<FlowField>.from(current.fields);
    final idx = fields.indexWhere((f) => f.key == fieldKey);
    if (idx == -1) return;
    final targetIdx = idx + delta;
    if (targetIdx < 0 || targetIdx >= fields.length) return;

    final item = fields.removeAt(idx);
    fields.insert(targetIdx, item);
    _replaceStep(current.copyWith(fields: fields));
  }

  // ---------------------------------------------------------------------------
  // Branch Rule operations (Phase 5)
  // ---------------------------------------------------------------------------

  void addBranchRuleToSelectedStep(BranchRule rule) {
    final current = state.selectedStep;
    if (current == null) return;

    final next = current.next.copyWith(
      rules: [...current.next.rules, rule],
    );
    _replaceStep(current.copyWith(next: next));
  }

  void removeBranchRuleFromSelectedStep(int index) {
    final current = state.selectedStep;
    if (current == null) return;

    final rules = List<BranchRule>.from(current.next.rules);
    if (index < 0 || index >= rules.length) return;
    rules.removeAt(index);
    _replaceStep(current.copyWith(next: current.next.copyWith(rules: rules)));
  }

  // ---------------------------------------------------------------------------
  // Server Sync (Debounced Draft Save, Publish, Reset, Preview, AI Edit)
  // ---------------------------------------------------------------------------

  void _replaceStep(FlowStep updatedStep) {
    final steps = [
      for (final s in state.draft.steps)
        if (s.id == updatedStep.id) updatedStep else s,
    ];
    _applyDraftMutation(state.draft.copyWith(steps: steps));
  }

  void _applyDraftMutation(FlowDefinition newDraft) {
    state = state.copyWith(
      snapshot: state.snapshot.copyWith(draft: newDraft),
      clearError: true,
      clearStatus: true,
    );

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, _flushDraftToServer);
  }

  Future<void> _flushDraftToServer() async {
    state = state.copyWith(isSavingDraft: true);
    try {
      final serverSnapshot = await _api.saveDraft(state.draft);
      state = state.copyWith(
        snapshot: serverSnapshot,
        isSavingDraft: false,
      );
      await refreshPreview();
    } catch (e) {
      state = state.copyWith(
        isSavingDraft: false,
        errorMessage: 'Draft kaydedilemedi: $e',
      );
    }
  }

  Future<void> publishFlow() async {
    _debounceTimer?.cancel();
    state = state.copyWith(
      isPublishing: true,
      clearError: true,
      clearStatus: true,
    );
    try {
      await _api.saveDraft(state.draft);
      final publishedSnapshot = await _api.publish();
      state = state.copyWith(
        snapshot: publishedSnapshot,
        isPublishing: false,
        statusMessage:
            'v${publishedSnapshot.publishedVersion} başarıyla yayınlandı! (SSE gönderildi)',
      );
      await refreshPreview();
    } catch (e) {
      state = state.copyWith(
        isPublishing: false,
        errorMessage: 'Yayınlama hatası: $e',
      );
    }
  }

  Future<void> resetFlow() async {
    _debounceTimer?.cancel();
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearStatus: true,
    );
    try {
      final resetSnapshot = await _api.reset();
      state = state.copyWith(
        snapshot: resetSnapshot,
        selectedStepId: resetSnapshot.draft.steps.firstOrNull?.id,
        isLoading: false,
        statusMessage:
            'Varsayılan şablona dönüldü ve v${resetSnapshot.publishedVersion} yayınlandı.',
      );
      await refreshPreview();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sıfırlama hatası: $e',
      );
    }
  }

  Future<void> applyAiPrompt(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;

    _debounceTimer?.cancel();
    state = state.copyWith(
      isAiBusy: true,
      clearError: true,
      clearStatus: true,
    );
    try {
      await _api.saveDraft(state.draft);
      final res = await _api.aiEdit(trimmed);
      state = state.copyWith(
        snapshot: res.snapshot,
        isAiBusy: false,
        statusMessage: '✨ ${res.summary}',
      );
      await refreshPreview();
    } catch (e) {
      state = state.copyWith(
        isAiBusy: false,
        errorMessage: 'AI düzenleme hatası: $e',
      );
    }
  }

  Future<void> refreshPreview() async {
    try {
      final stepId = state.selectedStep?.id;
      final messages = await _api.previewStep(stepId);
      state = state.copyWith(previewMessages: messages);
    } catch (_) {}
  }

  String generateUniqueFieldKey(String label) {
    final slug = label
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = slug.isEmpty ? 'field_${++_idCounter}' : slug;
    final existingKeys = {
      for (final s in state.draft.steps)
        for (final f in s.fields) f.key,
    };
    if (!existingKeys.contains(base)) return base;
    var suffix = 2;
    while (existingKeys.contains('${base}_$suffix')) {
      suffix++;
    }
    return '${base}_$suffix';
  }
}

final flowEditorProvider =
    AutoDisposeNotifierProvider<FlowEditorController, FlowEditorState>(
  FlowEditorController.new,
);

