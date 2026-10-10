import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/uploaded_file.dart';
import '../viewmodels/gallery_viewmodel.dart';
import 'widgets.dart';

class GalleryView extends StatelessWidget {
  const GalleryView({super.key});

  Future<void> _pick(BuildContext context) async {
    final images = await ImagePicker().pickMultiImage();
    if (images.isNotEmpty && context.mounted) {
      context.read<GalleryViewModel>().select(images);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GalleryViewModel>();
    final textTheme = Theme.of(context).textTheme;
    final mode = vm.concurrent ? 'concurrente' : 'secuencial';

    return Scaffold(
      appBar: AppBar(title: const Text('Galería')),
      body: RefreshIndicator(
        onRefresh: vm.loadFiles,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Procesar y subir: validar, redimensionar a $maxWidthLabel, comprimir y subir',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Secuencial')),
                ButtonSegment(value: true, label: Text('Concurrente')),
              ],
              selected: {vm.concurrent},
              onSelectionChanged: vm.isRunning
                  ? null
                  : (value) => vm.setMode(concurrent: value.first),
            ),
            const SizedBox(height: 4),
            Text(
              vm.concurrent
                  ? 'Todas a la vez: Future.wait y un isolate por imagen'
                  : 'Una imagen a la vez, cada una espera a la anterior',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(
                vm.selected.isEmpty
                    ? 'Seleccionar imágenes'
                    : '${vm.selected.length} imágenes seleccionadas',
              ),
              onPressed: vm.isRunning ? null : () => _pick(context),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text(
                vm.selected.isEmpty
                    ? 'Ejecutar'
                    : 'Ejecutar en $mode (${vm.selected.length} imágenes)',
              ),
              onPressed: vm.selected.isEmpty || vm.isRunning ? null : vm.run,
            ),
            if (vm.isRunning) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (vm.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  vm.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (vm.history.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Historial', style: textTheme.titleMedium),
              for (final log in vm.history) _RunLogTile(log),
            ],
            if (vm.results.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Último intento', style: textTheme.titleMedium),
              for (final result in vm.results) _ResultTile(result),
            ],
            const SizedBox(height: 20),
            Text(
              'Mis archivos (${vm.files.length})',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [for (final file in vm.files) _FileTile(file)],
            ),
          ],
        ),
      ),
    );
  }
}

class _RunLogTile extends StatelessWidget {
  const _RunLogTile(this.log);

  final RunLog log;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Text(
        '#${log.number}',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      title: Text(
        '${log.concurrent ? 'Concurrente' : 'Secuencial'} · ${log.imageCount} imágenes',
      ),
      subtitle: log.failed == 0 ? null : Text('${log.failed} con error'),
      trailing: Text(
        formatDuration(log.elapsed),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

const maxWidthLabel = '1280 px';

class _ResultTile extends StatelessWidget {
  const _ResultTile(this.result);

  final ImageResult result;

  @override
  Widget build(BuildContext context) {
    final processed = result.processed;
    final file = result.file;
    final error = result.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        error == null ? Icons.check_circle : Icons.error,
        color: error == null
            ? Colors.green
            : Theme.of(context).colorScheme.error,
      ),
      title: Text(result.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        error ??
            '${processed!.originalWidth}×${processed.originalHeight} → ${processed.width}×${processed.height} · '
                '${formatBytes(result.originalBytes!)} → ${formatBytes(file!.size)}\n${file.url}',
      ),
      trailing: Text(formatDuration(result.elapsed)),
      isThreeLine: error == null,
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile(this.file);

  final UploadedFile file;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () async {
        final vm = context.read<GalleryViewModel>();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminar archivo'),
            content: Text('${file.originalName}\n${file.url}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
        if (confirmed == true) await vm.deleteFile(file);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: file.isImage
            ? Image.network(fileUrl(file.url), fit: BoxFit.cover)
            : const ColoredBox(
                color: Colors.black12,
                child: Icon(Icons.picture_as_pdf),
              ),
      ),
    );
  }
}
