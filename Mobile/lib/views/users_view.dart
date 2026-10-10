import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/users_viewmodel.dart';
import 'user_detail_view.dart';
import 'user_form_view.dart';
import 'widgets.dart';

class UsersView extends StatelessWidget {
  const UsersView({super.key});

  // Child screens share this same ViewModel instance.
  void _open(BuildContext context, Widget page) {
    final vm = context.read<UsersViewModel>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: vm, child: page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<UsersViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Crear usuario',
        onPressed: () => _open(context, const UserFormView()),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(
          children: [
            if (vm.isLoading) const LinearProgressIndicator(),
            if (vm.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  vm.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final user in vm.users)
              ListTile(
                leading: UserAvatar(user: user),
                title: Text(user.fullName),
                subtitle: Text(user.email),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, UserDetailView(userId: user.id)),
              ),
          ],
        ),
      ),
    );
  }
}
