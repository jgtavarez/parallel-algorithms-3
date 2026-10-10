import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../viewmodels/users_viewmodel.dart';
import 'user_form_view.dart';
import 'widgets.dart';

class UserDetailView extends StatelessWidget {
  const UserDetailView({super.key, required this.userId});

  final int userId;

  Future<void> _changePhoto(BuildContext context) async {
    final vm = context.read<UsersViewModel>();
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final ok = await vm.changePhoto(userId, image);
    if (context.mounted) {
      showMessage(context, ok ? 'Foto actualizada' : vm.error!);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final vm = context.read<UsersViewModel>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: const Text('También se eliminarán sus archivos.'),
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
    if (confirmed != true) return;
    final ok = await vm.delete(userId);
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      showMessage(context, vm.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<UsersViewModel>();
    final user = vm.byId(userId);
    if (user == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(
        title: Text(user.fullName),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: vm,
                  child: UserFormView(user: user),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete),
            onPressed: vm.isLoading ? null : () => _delete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(child: UserAvatar(user: user, radius: 56)),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: Text(user.photo == null ? 'Subir foto' : 'Cambiar foto'),
              onPressed: vm.isLoading ? null : () => _changePhoto(context),
            ),
          ),
          if (vm.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 24),
          ListTile(title: const Text('ID'), subtitle: Text('${user.id}')),
          ListTile(title: const Text('Nombre'), subtitle: Text(user.firstName)),
          ListTile(
            title: const Text('Apellido'),
            subtitle: Text(user.lastName),
          ),
          ListTile(title: const Text('Email'), subtitle: Text(user.email)),
          ListTile(
            title: const Text('Creado'),
            subtitle: Text(formatDate(user.createdAt)),
          ),
          if (user.photo != null)
            ListTile(
              title: const Text('Foto'),
              subtitle: SelectableText(fileUrl(user.photo!)),
            ),
        ],
      ),
    );
  }
}
