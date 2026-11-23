import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flow_compiler/flow_compiler.dart';
import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'photo_uploader.dart';

/// The `PhotoPicker` component: our own widget, added on top of the basic
/// catalog. The schema comes from flow_compiler, so the server and the
/// Player agree on the exact same contract.
ComponentImplementation photoPickerComponent(PhotoUploader uploader) =>
    ComponentImplementation(
      name: 'PhotoPicker',
      schema: Schema.fromMap(FlowCatalogSchemas.photoPicker),
      builder: (context, node, props, buildChild) => PhotoPickerField(
        label: props.string('label') ?? 'Fotoğraf',
        // Current value of the bound path, e.g. /answers/avatar.
        path: props.string('value'),
        // Writes back to that path. Null when the server sent a literal.
        onChanged: _writerOf(props, 'value'),
        error: props.validationErrors.firstOrNull,
        uploader: uploader,
      ),
    );

/// Same idea as the basic catalog's private `writerFor`: resolve the bound
/// path and return a function that writes a new value into the data model.
ValueChanged<String>? _writerOf(ComponentProps props, String key) {
  final binding = props.writable(key);
  if (binding == null) return null;
  return (value) {
    try {
      binding.set(value);
    } on A2uiDataError {
      // The renderer already reports binding errors; nothing to add here.
    }
  };
}

class PhotoPickerField extends StatefulWidget {
  const PhotoPickerField({
    super.key,
    required this.label,
    required this.path,
    required this.onChanged,
    required this.uploader,
    this.error,
  });

  final String label;
  final String? path;
  final ValueChanged<String>? onChanged;
  final PhotoUploader uploader;
  final String? error;

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  bool _busy = false;
  String? _uploadError;

  bool get _hasPhoto => widget.path != null && widget.path!.isNotEmpty;

  Future<void> _pick() async {
    final write = widget.onChanged;
    if (write == null || _busy) return;
    setState(() {
      _busy = true;
      _uploadError = null;
    });
    try {
      final path = await widget.uploader.pickAndUpload();
      if (path != null) write(path);
    } on Object catch (e) {
      _uploadError = e is PhotoUploadException ? e.message : 'Yükleme başarısız.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _uploadError ?? widget.error;
    final enabled = widget.onChanged != null && !_busy;

    final Widget preview = _busy
        ? const SizedBox(
            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
        : _hasPhoto
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.uploader.resolve(widget.path!),
                  key: const ValueKey('photo_picker_preview'),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              )
            : const Icon(Icons.add_a_photo_outlined, size: 32);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('photo_picker_tap'),
          onTap: enabled ? _pick : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: error != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: 64, height: 64, child: Center(child: preview)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _busy
                        ? 'Yükleniyor...'
                        : _hasPhoto
                            ? 'Fotoğrafı değiştir'
                            : 'Fotoğraf seç',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}
