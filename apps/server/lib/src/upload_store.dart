import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Stores photos the Player uploads before a step is submitted.
///
/// The photo itself never travels inside the A2UI data model. The Player
/// uploads the bytes here, gets back a short path (`/uploads/p_xxx.jpg`) and
/// writes only that path into `/answers/<key>`.
class UploadStore {
  UploadStore({String? directory, this.maxBytes = 5 * 1024 * 1024})
      : _directory = directory;

  final String? _directory;
  final int maxBytes;
  final Map<String, Uint8List> _memory = {};
  final Random _random = Random.secure();

  static const Map<String, String> contentTypes = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
  };

  /// Saves [bytes] and returns the public path, e.g. `/uploads/p_ab12.jpg`.
  /// Throws [UploadException] for an unsupported type or a too large file.
  String save(Uint8List bytes, String? contentType) {
    final mime = (contentType ?? '').split(';').first.trim().toLowerCase();
    final ext = contentTypes[mime];
    if (ext == null) {
      throw UploadException('Desteklenmeyen dosya tipi: $mime');
    }
    if (bytes.isEmpty) throw UploadException('Dosya boş.');
    if (bytes.length > maxBytes) {
      throw UploadException('Dosya en fazla ${maxBytes ~/ (1024 * 1024)} MB olabilir.');
    }
    final id = 'p_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(1 << 32).toRadixString(36)}';
    final name = '$id.$ext';
    final dir = _directory;
    if (dir == null) {
      _memory[name] = bytes;
    } else {
      final file = File('$dir/$name');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
    }
    return '/uploads/$name';
  }

  /// Returns the bytes and content type of [name], or null if missing.
  ({Uint8List bytes, String contentType})? read(String name) {
    // Only names we generated: no slashes, no traversal.
    if (!RegExp(r'^p_[a-z0-9]+\.(jpg|png|webp|gif)$').hasMatch(name)) {
      return null;
    }
    final ext = name.split('.').last;
    final type =
        contentTypes.entries.firstWhere((e) => e.value == ext).key;
    final dir = _directory;
    if (dir == null) {
      final bytes = _memory[name];
      return bytes == null ? null : (bytes: bytes, contentType: type);
    }
    final file = File('$dir/$name');
    if (!file.existsSync()) return null;
    return (bytes: file.readAsBytesSync(), contentType: type);
  }
}

class UploadException implements Exception {
  UploadException(this.message);
  final String message;
  @override
  String toString() => message;
}
