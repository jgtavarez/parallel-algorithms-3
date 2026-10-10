import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const maxWidth = 1280;

class InvalidImageException implements Exception {
  const InvalidImageException();

  @override
  String toString() => 'No es una imagen válida';
}

class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int originalWidth;
  final int originalHeight;
  final int width;
  final int height;
}

// Decoding and re-encoding is CPU work, so each image runs in its own isolate
// (a separate thread with its own memory) instead of blocking the UI.
Future<ProcessedImage> processInIsolate(Uint8List raw) =>
    Isolate.run(() => processImage(raw));

ProcessedImage processImage(Uint8List raw) {
  final image = _decode(raw);
  if (image == null) throw const InvalidImageException();

  final resized = image.width > maxWidth
      ? img.copyResize(image, width: maxWidth)
      : image;
  return ProcessedImage(
    bytes: img.encodeJpg(resized, quality: 80),
    originalWidth: image.width,
    originalHeight: image.height,
    width: resized.width,
    height: resized.height,
  );
}

// The decoder can throw on corrupt data instead of returning null.
img.Image? _decode(Uint8List raw) {
  try {
    return img.decodeImage(raw);
  } catch (_) {
    return null;
  }
}
