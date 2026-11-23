import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

const _deepEquals = DeepCollectionEquality();

/// Supported field types in A2UI Flow Studio.
enum FieldType {
  text('text', 'Kısa Metin (Text)'),
  longText('longText', 'Uzun Metin (Long Text)'),
  email('email', 'E-posta (Email)'),
  number('number', 'Sayı (Number)'),
  date('date', 'Tarih (Date)'),
  singleChoice('singleChoice', 'Tek Seçim (Single Choice)'),
  multiChoice('multiChoice', 'Çoklu Seçim (Multi Choice)'),
  checkbox('checkbox', 'Onay Kutusu (Checkbox)'),
  slider('slider', 'Kaydırıcı (Slider)'),
  photo('photo', 'Fotoğraf (Photo)');

  const FieldType(this.jsonValue, this.displayName);

  final String jsonValue;
  final String displayName;

  bool get isChoice =>
      this == FieldType.singleChoice || this == FieldType.multiChoice;

  bool get hasMinMax => this == FieldType.number || this == FieldType.slider;

  static FieldType fromJson(String value) {
    return FieldType.values.firstWhere(
      (t) => t.jsonValue == value,
      orElse: () => FieldType.text,
    );
  }
}

/// Option item for singleChoice and multiChoice fields.
@immutable
class FieldOption {
  const FieldOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  FieldOption copyWith({
    String? value,
    String? label,
  }) =>
      FieldOption(
        value: value ?? this.value,
        label: label ?? this.label,
      );

  factory FieldOption.fromJson(Map<String, dynamic> json) => FieldOption(
        value: (json['value'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'label': label,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldOption && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);
}

/// A single form field inside a [FlowStep].
@immutable
class FlowField {
  const FlowField({
    required this.key,
    required this.type,
    required this.label,
    this.placeholder,
    this.required = false,
    this.options,
    this.min,
    this.max,
    this.minLength,
  });

  /// Immutable unique key used in `/answers/{key}` data model path.
  final String key;
  final FieldType type;
  final String label;
  final String? placeholder;
  final bool required;
  final List<FieldOption>? options;
  final num? min;
  final num? max;
  final int? minLength;

  FlowField copyWith({
    String? key,
    FieldType? type,
    String? label,
    String? placeholder,
    bool clearPlaceholder = false,
    bool? required,
    List<FieldOption>? options,
    bool clearOptions = false,
    num? min,
    bool clearMin = false,
    num? max,
    bool clearMax = false,
    int? minLength,
    bool clearMinLength = false,
  }) =>
      FlowField(
        key: key ?? this.key,
        type: type ?? this.type,
        label: label ?? this.label,
        placeholder:
            clearPlaceholder ? null : (placeholder ?? this.placeholder),
        required: required ?? this.required,
        options: clearOptions ? null : (options ?? this.options),
        min: clearMin ? null : (min ?? this.min),
        max: clearMax ? null : (max ?? this.max),
        minLength: clearMinLength ? null : (minLength ?? this.minLength),
      );

  factory FlowField.fromJson(Map<String, dynamic> json) => FlowField(
        key: (json['key'] as String?) ?? '',
        type: FieldType.fromJson((json['type'] as String?) ?? 'text'),
        label: (json['label'] as String?) ?? '',
        placeholder: json['placeholder'] as String?,
        required: (json['required'] as bool?) ?? false,
        options: (json['options'] as List<dynamic>?)
            ?.map((e) => FieldOption.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        min: json['min'] as num?,
        max: json['max'] as num?,
        minLength: (json['minLength'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type.jsonValue,
        'label': label,
        if (placeholder != null && placeholder!.isNotEmpty)
          'placeholder': placeholder,
        'required': required,
        if (options != null)
          'options': options!.map((e) => e.toJson()).toList(),
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (minLength != null) 'minLength': minLength,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowField &&
          other.key == key &&
          other.type == type &&
          other.label == label &&
          other.placeholder == placeholder &&
          other.required == required &&
          _deepEquals.equals(other.options, options) &&
          other.min == min &&
          other.max == max &&
          other.minLength == minLength;

  @override
  int get hashCode => Object.hash(
        key,
        type,
        label,
        placeholder,
        required,
        _deepEquals.hash(options),
        min,
        max,
        minLength,
      );
}

/// Conditional branching rule evaluated when advancing from a step.
@immutable
class BranchRule {
  const BranchRule({
    required this.fieldKey,
    required this.equals,
    required this.goToStepId,
  });

  final String fieldKey;
  final String equals;
  final String goToStepId;

  BranchRule copyWith({
    String? fieldKey,
    String? equals,
    String? goToStepId,
  }) =>
      BranchRule(
        fieldKey: fieldKey ?? this.fieldKey,
        equals: equals ?? this.equals,
        goToStepId: goToStepId ?? this.goToStepId,
      );

  factory BranchRule.fromJson(Map<String, dynamic> json) => BranchRule(
        fieldKey: (json['fieldKey'] as String?) ?? '',
        equals: (json['equals'] as String?) ?? '',
        goToStepId: (json['goToStepId'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'fieldKey': fieldKey,
        'equals': equals,
        'goToStepId': goToStepId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BranchRule &&
          other.fieldKey == fieldKey &&
          other.equals == equals &&
          other.goToStepId == goToStepId;

  @override
  int get hashCode => Object.hash(fieldKey, equals, goToStepId);
}

/// Navigation rules after a step is submitted.
@immutable
class StepNext {
  const StepNext({
    this.defaultStepId,
    this.rules = const [],
  });

  /// Null means the flow finishes and transitions to the summary surface.
  final String? defaultStepId;
  final List<BranchRule> rules;

  StepNext copyWith({
    String? defaultStepId,
    bool clearDefaultStepId = false,
    List<BranchRule>? rules,
  }) =>
      StepNext(
        defaultStepId:
            clearDefaultStepId ? null : (defaultStepId ?? this.defaultStepId),
        rules: rules ?? this.rules,
      );

  factory StepNext.fromJson(Map<String, dynamic> json) => StepNext(
        defaultStepId: json['defaultStepId'] as String?,
        rules: (json['rules'] as List<dynamic>?)
                ?.map((e) =>
                    BranchRule.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'defaultStepId': defaultStepId,
        'rules': rules.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepNext &&
          other.defaultStepId == defaultStepId &&
          _deepEquals.equals(other.rules, rules);

  @override
  int get hashCode => Object.hash(defaultStepId, _deepEquals.hash(rules));
}

/// A step in the onboarding flow.
@immutable
class FlowStep {
  const FlowStep({
    required this.id,
    required this.title,
    this.description,
    required this.fields,
    this.submitLabel = 'Devam Et',
    this.next = const StepNext(),
  });

  final String id;
  final String title;
  final String? description;
  final List<FlowField> fields;
  final String submitLabel;
  final StepNext next;

  FlowStep copyWith({
    String? id,
    String? title,
    String? description,
    bool clearDescription = false,
    List<FlowField>? fields,
    String? submitLabel,
    StepNext? next,
  }) =>
      FlowStep(
        id: id ?? this.id,
        title: title ?? this.title,
        description:
            clearDescription ? null : (description ?? this.description),
        fields: fields ?? this.fields,
        submitLabel: submitLabel ?? this.submitLabel,
        next: next ?? this.next,
      );

  factory FlowStep.fromJson(Map<String, dynamic> json) => FlowStep(
        id: (json['id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        description: json['description'] as String?,
        fields: (json['fields'] as List<dynamic>?)
                ?.map((e) =>
                    FlowField.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        submitLabel: (json['submitLabel'] as String?) ?? 'Devam Et',
        next: json['next'] is Map
            ? StepNext.fromJson(Map<String, dynamic>.from(json['next'] as Map))
            : const StepNext(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'fields': fields.map((e) => e.toJson()).toList(),
        'submitLabel': submitLabel,
        'next': next.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowStep &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          _deepEquals.equals(other.fields, fields) &&
          other.submitLabel == submitLabel &&
          other.next == next;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        description,
        _deepEquals.hash(fields),
        submitLabel,
        next,
      );
}

/// Complete onboarding flow definition.
@immutable
class FlowDefinition {
  const FlowDefinition({
    required this.id,
    required this.title,
    required this.steps,
  });

  final String id;
  final String title;
  final List<FlowStep> steps;

  FlowStep? stepById(String stepId) =>
      steps.firstWhereOrNull((s) => s.id == stepId);

  FlowDefinition copyWith({
    String? id,
    String? title,
    List<FlowStep>? steps,
  }) =>
      FlowDefinition(
        id: id ?? this.id,
        title: title ?? this.title,
        steps: steps ?? this.steps,
      );

  factory FlowDefinition.fromJson(Map<String, dynamic> json) => FlowDefinition(
        id: (json['id'] as String?) ?? 'onboarding',
        title: (json['title'] as String?) ?? '',
        steps: (json['steps'] as List<dynamic>?)
                ?.map((e) =>
                    FlowStep.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'steps': steps.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowDefinition &&
          other.id == id &&
          other.title == title &&
          _deepEquals.equals(other.steps, steps);

  @override
  int get hashCode => Object.hash(id, title, _deepEquals.hash(steps));
}

/// Snapshot of draft and published flow states held by the server.
@immutable
class FlowSnapshot {
  const FlowSnapshot({
    required this.draft,
    required this.published,
    required this.publishedVersion,
  });

  final FlowDefinition draft;
  final FlowDefinition published;
  final int publishedVersion;

  bool get hasUnpublishedChanges => draft != published;

  FlowSnapshot copyWith({
    FlowDefinition? draft,
    FlowDefinition? published,
    int? publishedVersion,
  }) =>
      FlowSnapshot(
        draft: draft ?? this.draft,
        published: published ?? this.published,
        publishedVersion: publishedVersion ?? this.publishedVersion,
      );

  factory FlowSnapshot.fromJson(Map<String, dynamic> json) => FlowSnapshot(
        draft: FlowDefinition.fromJson(
          Map<String, dynamic>.from(json['draft'] as Map),
        ),
        published: FlowDefinition.fromJson(
          Map<String, dynamic>.from(json['published'] as Map),
        ),
        publishedVersion: (json['publishedVersion'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'draft': draft.toJson(),
        'published': published.toJson(),
        'publishedVersion': publishedVersion,
        'hasUnpublishedChanges': hasUnpublishedChanges,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowSnapshot &&
          other.draft == draft &&
          other.published == published &&
          other.publishedVersion == publishedVersion;

  @override
  int get hashCode => Object.hash(draft, published, publishedVersion);
}

