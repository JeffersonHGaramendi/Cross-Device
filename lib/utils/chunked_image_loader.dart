import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

class ChunkedImageLoader {
  /// Decodifica una imagen byte a byte informando progreso entre 0.0 y 1.0
  static Future<img.Image?> decodeWithProgress(
    Uint8List imageBytes,
    void Function(double progress) onProgress,
  ) async {
    const int chunkSize = 64 * 1024;
    final int total = imageBytes.length;
    int loaded = 0;
    final buffer = BytesBuilder();

    while (loaded < total) {
      final end = (loaded + chunkSize).clamp(0, total);
      buffer.add(imageBytes.sublist(loaded, end));
      loaded = end;
      onProgress(loaded / total);
      await Future.delayed(const Duration(milliseconds: 10));
    }

    return img.decodeImage(buffer.toBytes());
  }

  /// Convierte una imagen `img.Image` a `ui.Image` para pintarla en Flutter
  static Future<ui.Image> convertToUiImage(img.Image image) async {
    final completer = Completer<ui.Image>();
    final encodedBytes = Uint8List.fromList(img.encodePng(image));
    ui.decodeImageFromList(encodedBytes, completer.complete);
    return completer.future;
  }
}
