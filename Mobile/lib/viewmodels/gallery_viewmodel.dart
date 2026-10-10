import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/uploaded_file.dart';
import '../repositories/file_repository.dart';
import '../services/image_processing.dart';

class ImageResult {
  const ImageResult({
    required this.name,
    required this.elapsed,
    this.originalBytes,
    this.processed,
    this.file,
    this.error,
  });

  final String name;
  final Duration elapsed;
  final int? originalBytes;
  final ProcessedImage? processed;
  final UploadedFile? file;
  final String? error;
}

class RunLog {
  const RunLog({
    required this.number,
    required this.concurrent,
    required this.imageCount,
    required this.failed,
    required this.elapsed,
  });

  final int number;
  final bool concurrent;
  final int imageCount;
  final int failed;
  final Duration elapsed;
}

class GalleryViewModel extends ChangeNotifier {
  GalleryViewModel(this._files);

  final FileRepository _files;

  bool concurrent = true;
  List<XFile> selected = [];
  List<ImageResult> results = [];
  List<RunLog> history = [];
  List<UploadedFile> files = [];
  bool isRunning = false;
  String? error;

  Future<void> loadFiles() async {
    try {
      files = await _files.getMine();
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void setMode({required bool concurrent}) {
    this.concurrent = concurrent;
    notifyListeners();
  }

  void select(List<XFile> images) {
    selected = images;
    results = [];
    notifyListeners();
  }

  Future<void> run() async {
    if (selected.isEmpty || isRunning) return;
    isRunning = true;
    error = null;
    results = [];
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    if (concurrent) {
      // Every image starts at once: each one is processed in its own isolate
      // and uploaded while the others are still working.
      results = await Future.wait(selected.map(_processAndUpload));
    } else {
      for (final image in selected) {
        results = [...results, await _processAndUpload(image)];
        notifyListeners();
      }
    }

    history = [
      RunLog(
        number: history.length + 1,
        concurrent: concurrent,
        imageCount: selected.length,
        failed: results.where((result) => result.error != null).length,
        elapsed: stopwatch.elapsed,
      ),
      ...history,
    ];
    isRunning = false;
    await loadFiles();
  }

  Future<void> deleteFile(UploadedFile file) async {
    try {
      await _files.delete(file.id);
      files = files.where((item) => item.id != file.id).toList();
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  // Validate (decode), get info, resize/compress, upload. A failure only affects its own image.
  Future<ImageResult> _processAndUpload(XFile image) async {
    final stopwatch = Stopwatch()..start();
    try {
      final raw = await image.readAsBytes();
      final processed = await processInIsolate(raw);
      final name = '${image.name.split('.').first}.jpg';
      final file = await _files.upload(processed.bytes, name);
      return ImageResult(
        name: image.name,
        elapsed: stopwatch.elapsed,
        originalBytes: raw.length,
        processed: processed,
        file: file,
      );
    } catch (e) {
      return ImageResult(
        name: image.name,
        elapsed: stopwatch.elapsed,
        error: '$e',
      );
    }
  }
}
