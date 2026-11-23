import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Picks a photo on the device and uploads it to the server.
///
/// Kept behind an interface so widget tests can use a fake without a camera,
/// a gallery or a network.
abstract interface class PhotoUploader {
  /// Opens the picker, uploads the chosen photo and returns the server path
  /// (`/uploads/p_xxx.jpg`). Returns null when the user cancels.
  /// Throws [PhotoUploadException] when the upload fails.
  Future<String?> pickAndUpload();

  /// Full URL for a server path, so `Image.network` can show it.
  String resolve(String path);
}

class PhotoUploadException implements Exception {
  PhotoUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Real implementation: image_picker + `POST /uploads`.
class HttpPhotoUploader implements PhotoUploader {
  HttpPhotoUploader({
    required this.baseUrl,
    ImagePicker? picker,
    http.Client? client,
  })  : _picker = picker ?? ImagePicker(),
        _client = client ?? http.Client();

  final String baseUrl;
  final ImagePicker _picker;
  final http.Client _client;

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  @override
  String resolve(String path) => '$_base$path';

  @override
  Future<String?> pickAndUpload() async {
    // Resize on the device: the server only needs a profile-sized photo.
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final response = await _client.post(
      Uri.parse('$_base/uploads'),
      headers: {'Content-Type': _contentTypeOf(file)},
      body: bytes,
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw PhotoUploadException(
        body['error'] as String? ?? 'Yükleme başarısız (${response.statusCode}).',
      );
    }
    return body['path'] as String;
  }

  static String _contentTypeOf(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
