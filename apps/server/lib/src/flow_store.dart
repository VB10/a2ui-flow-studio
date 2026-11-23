import 'dart:convert';
import 'dart:io';

import 'package:flow_core/flow_core.dart';

/// Exception thrown when publishing an invalid flow definition.
class FlowPublishValidationException implements Exception {
  const FlowPublishValidationException(this.issues);

  final List<FlowValidationIssue> issues;
}

/// Manages in-memory [FlowSnapshot] with atomic persistence to `flow.json`.
class FlowStore {
  FlowStore({
    String? storagePath,
    FlowDefinition? initialTemplate,
  })  : _storagePath = storagePath,
        _template = initialTemplate ?? createDefaultFlowTemplate() {
    _loadOrInitialize();
  }

  final String? _storagePath;
  final FlowDefinition _template;
  late FlowSnapshot _snapshot;

  FlowSnapshot get snapshot => _snapshot;

  void _loadOrInitialize() {
    if (_storagePath != null) {
      final file = File(_storagePath);
      if (file.existsSync()) {
        try {
          final content = file.readAsStringSync();
          final jsonMap = jsonDecode(content) as Map<String, dynamic>;
          _snapshot = FlowSnapshot.fromJson(jsonMap);
          return;
        } catch (e) {
          stderr.writeln(
            '[FlowStore] Failed to load $_storagePath, falling back to template: $e',
          );
        }
      }
    }

    _snapshot = FlowSnapshot(
      draft: _template,
      published: _template,
      publishedVersion: 1,
    );
    _persistAtomically();
  }

  /// Updates the draft flow and persists atomically.
  FlowSnapshot saveDraft(FlowDefinition newDraft) {
    _snapshot = _snapshot.copyWith(draft: newDraft);
    _persistAtomically();
    return _snapshot;
  }

  /// Validates the current draft and promotes it to published, incrementing version.
  /// Throws [FlowPublishValidationException] if validation fails.
  FlowSnapshot publish() {
    final issues = FlowValidator.validateFlow(_snapshot.draft);
    if (issues.isNotEmpty) {
      throw FlowPublishValidationException(issues);
    }

    _snapshot = FlowSnapshot(
      draft: _snapshot.draft,
      published: _snapshot.draft,
      publishedVersion: _snapshot.publishedVersion + 1,
    );
    _persistAtomically();
    return _snapshot;
  }

  /// Resets both draft and published to the embedded template and increments version.
  FlowSnapshot resetToTemplate() {
    _snapshot = FlowSnapshot(
      draft: _template,
      published: _template,
      publishedVersion: _snapshot.publishedVersion + 1,
    );
    _persistAtomically();
    return _snapshot;
  }

  void _persistAtomically() {
    final path = _storagePath;
    if (path == null) return;

    try {
      final targetFile = File(path);
      targetFile.parent.createSync(recursive: true);
      final tempFile = File('$path.tmp');
      const encoder = JsonEncoder.withIndent('  ');
      tempFile.writeAsStringSync(encoder.convert(_snapshot.toJson()), flush: true);
      tempFile.renameSync(path);
    } catch (e) {
      stderr.writeln('[FlowStore] Atomic write failed for $path: $e');
    }
  }
}

