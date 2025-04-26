import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../models/device_info.dart';

class ImageSyncService {
  Uint8List? imageBytes;
  ui.Image? uiImage;
  bool hasImage = false;

  Future<ui.Image> loadImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (result) {
      completer.complete(result);
    });
    return completer.future;
  }

  void setImage(Uint8List bytes, ui.Image image) {
    imageBytes = bytes;
    uiImage = image;
    hasImage = true;
  }

  void clearImage() {
    imageBytes = null;
    uiImage = null;
    hasImage = false;
  }

  // Más métodos: compartir imágenes, preparar para sincronizar, etc.
}
