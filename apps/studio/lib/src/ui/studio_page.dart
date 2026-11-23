import 'dart:convert';

import 'package:flow_core/flow_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/flow_editor_controller.dart';
import 'submissions_tab.dart';

/// 3-Column Studio Web Editor for A2UI Flow Studio:
/// - Top Bar: Flow Title, Unpublished changes badge, Version chip, Reset & Publish buttons.
/// - Left Column: Step list (Add, Delete, Move Up/Down) + Level 2 AI Prompt Box.
/// - Middle Column: Selected step editor (Title, Description, Submit label, Fields CRUD, Branch Rules).
/// - Right Column: Tabs for A2UI JSON (`/flow/preview`) and Validation issues.
class StudioPage extends ConsumerStatefulWidget {
  const StudioPage({super.key});

  @override
  ConsumerState<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends ConsumerState<StudioPage> {
  final TextEditingController _aiPromptController = TextEditingController();

  @override
  void dispose() {
    _aiPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(flowEditorProvider);
    final controller = ref.read(flowEditorProvider.notifier);

    ref.listen<FlowEditorState>(flowEditorProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (next.statusMessage != null &&
          next.statusMessage != prev?.statusMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.statusMessage!),
            backgroundColor: const Color(0xFF15803D),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: _buildTopBar(context, editorState, controller),
      body: Column(
        children: [
          _buildAiPromptBar(context, editorState, controller),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Column: Step List
                SizedBox(
                  width: 280,
                  child: _StepListColumn(
                    state: editorState,
                    controller: controller,
                  ),
                ),
                const VerticalDivider(width: 1),
                // Middle Column: Selected Step & Fields Editor
                Expanded(
                  flex: 5,
                  child: _StepEditorColumn(
                    state: editorState,
                    controller: controller,
                  ),
                ),
                const VerticalDivider(width: 1),
                // Right Column: A2UI JSON & Validation Tabs
                Expanded(
                  flex: 4,
                  child: _InspectorColumn(
                    state: editorState,
                    controller: controller,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTopBar(
    BuildContext context,
    FlowEditorState state,
    FlowEditorController controller,
  ) {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE2E8F0)),
      ),
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1D4ED8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.account_tree_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'A2UI Flow Studio',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 240,
            child: TextFormField(
              key: ValueKey<String>('flow_title_${state.publishedVersion}'),
              initialValue: state.draft.title,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Akış Başlığı',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              onChanged: controller.updateFlowTitle,
            ),
          ),
          const SizedBox(width: 12),
          // Published Version Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Published v${state.publishedVersion}',
              style: const TextStyle(
                color: Color(0xFF1E40AF),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Unpublished Changes Badge
          if (state.hasUnpublishedChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFFD97706)),
                  SizedBox(width: 6),
                  Text(
                    'Unpublished changes',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 14, color: Color(0xFF15803D)),
                  SizedBox(width: 4),
                  Text(
                    'Senkronize',
                    style: TextStyle(
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          if (state.isSavingDraft) ...[
            const SizedBox(width: 10),
            Text(
              'Kaydediliyor...',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: state.isLoading ? null : controller.resetFlow,
          icon: const Icon(Icons.restore_rounded, size: 18),
          label: const Text('Reset'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          key: const Key('publish_button'),
          onPressed: state.canPublish ? controller.publishFlow : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
          ),
          icon: state.isPublishing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.rocket_launch_rounded, size: 18),
          label: const Text(
            'Publish',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildAiPromptBar(
    BuildContext context,
    FlowEditorState state,
    FlowEditorController controller,
  ) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: Color(0xFF7C3AED),
          ),
          const SizedBox(width: 8),
          const Text(
            'Seviye 2 AI Editör:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xFF5B21B6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const Key('ai_prompt_input'),
              controller: _aiPromptController,
              decoration: const InputDecoration(
                isDense: true,
                hintText:
                    'Örn: "Yaşınızı girin alanını ekle" veya "Öğrencilere bölümünü de sor"',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (value) {
                controller.applyAiPrompt(value);
                _aiPromptController.clear();
              },
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            key: const Key('ai_prompt_submit'),
            onPressed: state.isAiBusy
                ? null
                : () {
                    controller.applyAiPrompt(_aiPromptController.text);
                    _aiPromptController.clear();
                  },
            icon: state.isAiBusy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, size: 16),
            label: const Text('Uygula'),
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: const Text(
              '+ Yaş Alanı',
              style: TextStyle(fontSize: 12),
            ),
            onPressed: () =>
                controller.applyAiPrompt('İlk adıma Yaşınızı girin alanı ekle'),
          ),
          const SizedBox(width: 6),
          ActionChip(
            label: const Text(
              '+ Öğrenci Bölümü',
              style: TextStyle(fontSize: 12),
            ),
            onPressed: () =>
                controller.applyAiPrompt('Öğrencilere bölümünü de sor'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LEFT COLUMN: Step List
// =============================================================================

class _StepListColumn extends StatelessWidget {
  const _StepListColumn({
    required this.state,
    required this.controller,
  });

  final FlowEditorState state;
  final FlowEditorController controller;

  @override
  Widget build(BuildContext context) {
    final steps = state.draft.steps;
    final selectedId = state.selectedStep?.id;

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Adımlar (Steps)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const Key('add_step_button'),
                  onPressed: () => controller.addStep(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Adım Ekle'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: steps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final step = steps[index];
                final isSelected = step.id == selectedId;
                return Material(
                  color: isSelected
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => controller.selectStep(step.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: isSelected
                                ? const Color(0xFF2563EB)
                                : const Color(0xFFCBD5E1),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${step.id} • ${step.fields.length} alan',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Yukarı Taşı',
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            onPressed: index > 0
                                ? () => controller.moveStep(step.id, -1)
                                : null,
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                          IconButton(
                            tooltip: 'Aşağı Taşı',
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            onPressed: index < steps.length - 1
                                ? () => controller.moveStep(step.id, 1)
                                : null,
                            icon: const Icon(Icons.arrow_downward_rounded),
                          ),
                          IconButton(
                            tooltip: 'Adımı Sil',
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            color: Colors.red.shade600,
                            onPressed: () => controller.deleteStep(step.id),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MIDDLE COLUMN: Step & Fields Editor
// =============================================================================

class _StepEditorColumn extends StatelessWidget {
  const _StepEditorColumn({
    required this.state,
    required this.controller,
  });

  final FlowEditorState state;
  final FlowEditorController controller;

  @override
  Widget build(BuildContext context) {
    final step = state.selectedStep;
    if (step == null) {
      return const Center(
        child: Text('Düzenlemek için soldan bir adım seçin veya yeni adım ekleyin.'),
      );
    }

    final otherSteps =
        state.draft.steps.where((s) => s.id != step.id).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step Metadata Card
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Adım Ayarları (${step.id})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Chip(
                        label: Text(
                          'step.id sabit',
                          style: TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          key: ValueKey('step_title_${step.id}'),
                          initialValue: step.title,
                          decoration: const InputDecoration(
                            labelText: 'Adım Başlığı',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              controller.updateSelectedStep(title: v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('step_submit_${step.id}'),
                          initialValue: step.submitLabel,
                          decoration: const InputDecoration(
                            labelText: 'Buton Etiketi',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              controller.updateSelectedStep(submitLabel: v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey('step_desc_${step.id}'),
                    initialValue: step.description ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Açıklama (Opsiyonel)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        controller.updateSelectedStep(description: v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(
                      'step_next_${step.id}_${step.next.defaultStepId}',
                    ),
                    isExpanded: true,
                    initialValue: otherSteps.any(
                      (s) => s.id == step.next.defaultStepId,
                    )
                        ? step.next.defaultStepId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Varsayılan Sonraki Adım (Next)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Akışı Bitir (Özet Ekranı)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final s in otherSteps)
                        DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(
                            '${s.title} (${s.id})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (targetId) {
                      controller.updateSelectedStep(
                        next: StepNext(
                          defaultStepId: targetId,
                          rules: step.next.rules,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Fields Section Header
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                'Alanlar (Fields • ${step.fields.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('quick_add_age_button'),
                    onPressed: () {
                      final key = controller.generateUniqueFieldKey('age');
                      controller.addFieldToSelectedStep(
                        FlowField(
                          key: key,
                          type: FieldType.slider,
                          label: 'Yaşınızı girin',
                          required: true,
                          min: 18,
                          max: 80,
                        ),
                      );
                    },
                    icon: const Icon(Icons.linear_scale_rounded, size: 16),
                    label: const Text('Hızlı: Yaş Ekle'),
                  ),
                  FilledButton.icon(
                    key: const Key('add_field_button'),
                    onPressed: () => _showFieldDialog(context, controller),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Alan Ekle'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (step.fields.isEmpty)
            Card(
              elevation: 0,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Bu adımda henüz alan yok. "Alan Ekle" butonunu kullanın.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
            )
          else
            for (var i = 0; i < step.fields.length; i++) ...[
              _FieldCard(
                field: step.fields[i],
                index: i,
                total: step.fields.length,
                onMoveUp: i > 0
                    ? () => controller.moveFieldInSelectedStep(
                          step.fields[i].key,
                          -1,
                        )
                    : null,
                onMoveDown: i < step.fields.length - 1
                    ? () => controller.moveFieldInSelectedStep(
                          step.fields[i].key,
                          1,
                        )
                    : null,
                onEdit: () => _showFieldDialog(
                  context,
                  controller,
                  existingField: step.fields[i],
                ),
                onDelete: () =>
                    controller.deleteFieldFromSelectedStep(step.fields[i].key),
              ),
              const SizedBox(height: 8),
            ],

          const SizedBox(height: 16),

          // Branch Rules Section (Phase 5)
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.call_split_rounded,
                        size: 18,
                        color: Color(0xFF0F172A),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Koşullu Dallanma Kuralları (Branch Rules)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: otherSteps.isEmpty || step.fields.isEmpty
                            ? null
                            : () => _showBranchRuleDialog(
                                  context,
                                  controller,
                                  step,
                                  otherSteps,
                                ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Kural Ekle'),
                      ),
                    ],
                  ),
                  if (step.next.rules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Koşul tanımlanmadı. Submit edildiğinde varsayılan sonraki adıma geçilir.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < step.next.rules.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 18,
                        ),
                        title: Text(
                          'Eğer "${step.next.rules[i].fieldKey}" == "${step.next.rules[i].equals}" → "${step.next.rules[i].goToStepId}" adımına git',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () =>
                              controller.removeBranchRuleFromSelectedStep(i),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFieldDialog(
    BuildContext context,
    FlowEditorController controller, {
    FlowField? existingField,
  }) async {
    final isEditing = existingField != null;
    final labelCtrl = TextEditingController(text: existingField?.label ?? '');
    final placeholderCtrl =
        TextEditingController(text: existingField?.placeholder ?? '');
    final minCtrl = TextEditingController(
      text: existingField?.min?.toString() ?? '18',
    );
    final maxCtrl = TextEditingController(
      text: existingField?.max?.toString() ?? '80',
    );
    final minLengthCtrl = TextEditingController(
      text: existingField?.minLength?.toString() ?? '',
    );
    final optionsCtrl = TextEditingController(
      text: existingField?.options
              ?.map((o) => '${o.value}:${o.label}')
              .join('\n') ??
          'opt1:Seçenek 1\nopt2:Seçenek 2',
    );

    var selectedType = existingField?.type ?? FieldType.text;
    var isRequired = existingField?.required ?? true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'Alanı Düzenle' : 'Yeni Alan Ekle'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isEditing)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Sabit Anahtar (field.key): ${existingField.key}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      DropdownButtonFormField<FieldType>(
                        isExpanded: true,
                        initialValue: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Alan Tipi (FieldType)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final t in FieldType.values)
                            DropdownMenuItem(
                              value: t,
                              child: Text(t.displayName),
                            ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedType = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('dialog_field_label'),
                        controller: labelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Etiket (Label) *',
                          hintText: 'Örn. Yaşınızı girin',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (selectedType != FieldType.checkbox &&
                          selectedType != FieldType.slider &&
                          !selectedType.isChoice) ...[
                        TextField(
                          controller: placeholderCtrl,
                          decoration: const InputDecoration(
                            labelText: 'İpucu Metni (Placeholder)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Zorunlu Alan (Required)'),
                        value: isRequired,
                        onChanged: (v) => setDialogState(() => isRequired = v),
                      ),
                      if (selectedType == FieldType.text ||
                          selectedType == FieldType.longText) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: minLengthCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minimum Karakter Uzunluğu (Opsiyonel)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (selectedType.hasMinMax) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: minCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Min Değer',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: maxCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Max Değer *',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (selectedType.isChoice) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: optionsCtrl,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText:
                                'Seçenekler (Her satıra value:Etiket formatında)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  key: const Key('dialog_save_field'),
                  onPressed: () {
                    final label = labelCtrl.text.trim();
                    if (label.isEmpty) return;

                    final key = isEditing
                        ? existingField.key
                        : controller.generateUniqueFieldKey(label);

                    List<FieldOption>? options;
                    if (selectedType.isChoice) {
                      options = [];
                      for (final line in optionsCtrl.text.split('\n')) {
                        final trimmed = line.trim();
                        if (trimmed.isEmpty) continue;
                        final parts = trimmed.split(':');
                        if (parts.length >= 2) {
                          options.add(
                            FieldOption(
                              value: parts[0].trim(),
                              label: parts.sublist(1).join(':').trim(),
                            ),
                          );
                        } else {
                          options.add(
                            FieldOption(value: trimmed, label: trimmed),
                          );
                        }
                      }
                    }

                    final field = FlowField(
                      key: key,
                      type: selectedType,
                      label: label,
                      placeholder: placeholderCtrl.text.trim().isEmpty
                          ? null
                          : placeholderCtrl.text.trim(),
                      required: isRequired,
                      min: selectedType.hasMinMax
                          ? num.tryParse(minCtrl.text.trim())
                          : null,
                      max: selectedType.hasMinMax
                          ? num.tryParse(maxCtrl.text.trim())
                          : null,
                      minLength: (selectedType == FieldType.text ||
                              selectedType == FieldType.longText)
                          ? int.tryParse(minLengthCtrl.text.trim())
                          : null,
                      options: options,
                    );

                    if (isEditing) {
                      controller.updateFieldInSelectedStep(key, field);
                    } else {
                      controller.addFieldToSelectedStep(field);
                    }
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(isEditing ? 'Güncelle' : 'Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showBranchRuleDialog(
    BuildContext context,
    FlowEditorController controller,
    FlowStep currentStep,
    List<FlowStep> otherSteps,
  ) async {
    var selectedFieldKey = currentStep.fields.first.key;
    var selectedTargetStepId = otherSteps.first.id;
    final equalsCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Koşullu Dallanma Kuralı Ekle'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedFieldKey,
                      decoration: const InputDecoration(
                        labelText: 'Kontrol Edilecek Alan (fieldKey)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final f in currentStep.fields)
                          DropdownMenuItem(
                            value: f.key,
                            child: Text('${f.label} (${f.key})'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedFieldKey = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: equalsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Eşitlik Değeri (equals)',
                        hintText: 'Örn. student veya developer',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedTargetStepId,
                      decoration: const InputDecoration(
                        labelText: 'Gidilecek Adım (goToStepId)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in otherSteps)
                          DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.title} (${s.id})'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedTargetStepId = v);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () {
                    final eq = equalsCtrl.text.trim();
                    if (eq.isEmpty) return;
                    controller.addBranchRuleToSelectedStep(
                      BranchRule(
                        fieldKey: selectedFieldKey,
                        equals: eq,
                        goToStepId: selectedTargetStepId,
                      ),
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.field,
    required this.index,
    required this.total,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
  });

  final FlowField field;
  final int index;
  final int total;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                field.type.jsonValue,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        field.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (field.required)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Zorunlu',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    'key: /answers/${field.key}'
                    '${field.min != null || field.max != null ? " • min: ${field.min ?? 0}, max: ${field.max ?? "-"}" : ""}'
                    '${field.options != null ? " • ${field.options!.length} seçenek" : ""}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Yukarı',
              iconSize: 18,
              onPressed: onMoveUp,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: 'Aşağı',
              iconSize: 18,
              onPressed: onMoveDown,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            IconButton(
              tooltip: 'Düzenle',
              iconSize: 18,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              iconSize: 18,
              color: Colors.red.shade600,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// RIGHT COLUMN: A2UI JSON & Validation Tabs
// =============================================================================

class _InspectorColumn extends StatelessWidget {
  const _InspectorColumn({
    required this.state,
    required this.controller,
  });

  final FlowEditorState state;
  final FlowEditorController controller;

  @override
  Widget build(BuildContext context) {
    final issues = state.validationIssues;
    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(state.previewMessages);

    return DefaultTabController(
      length: 3,
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              labelColor: const Color(0xFF1D4ED8),
              unselectedLabelColor: const Color(0xFF64748B),
              tabs: [
                const Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.data_object_rounded, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'A2UI JSON',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        issues.isEmpty
                            ? Icons.verified_rounded
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: issues.isEmpty
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Validation (${issues.length})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Tab(
                  key: Key('submissions_tab'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_rounded, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Gönderimler',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Compiled A2UI JSON Preview
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        color: const Color(0xFFF8FAFC),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'GET /flow/preview?stepId=${state.selectedStep?.id ?? ""}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'JSON Kopyala',
                              iconSize: 16,
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: jsonString),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('A2UI JSON panoya kopyalandı'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded),
                            ),
                            IconButton(
                              tooltip: 'Yenile',
                              iconSize: 16,
                              onPressed: controller.refreshPreview,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Container(
                          color: const Color(0xFF0F172A),
                          padding: const EdgeInsets.all(14),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              jsonString,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFFE2E8F0),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Tab 2: Validation Issues
                  issues.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 48,
                                  color: Color(0xFF16A34A),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Tüm doğrulama kontrolleri geçti!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Akış yayınlanmaya (Publish) hazır.',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: issues.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final issue = issues[index];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFFECACA),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFFDC2626),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          issue.message,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Color(0xFF991B1B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Kod: ${issue.code}'
                                          '${issue.stepId != null ? " • Adım: ${issue.stepId}" : ""}'
                                          '${issue.fieldKey != null ? " • Alan: ${issue.fieldKey}" : ""}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFFB91C1C),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                  // Tab 3: Player sessions & submissions
                  const SubmissionsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
