import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../viewmodels/users_viewmodel.dart';
import 'user_form.dart';

class UserFormView extends StatelessWidget {
  const UserFormView({super.key, this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<UsersViewModel>();
    final user = this.user;
    return Scaffold(
      appBar: AppBar(
        title: Text(user == null ? 'Crear usuario' : 'Editar usuario'),
      ),
      body: UserForm(
        user: user,
        submitLabel: 'Guardar',
        isLoading: vm.isLoading,
        error: vm.error,
        onSubmit: (input) async {
          final ok = user == null
              ? await vm.create(input)
              : await vm.update(user.id, input);
          if (ok && context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
