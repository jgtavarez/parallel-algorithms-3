import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/auth_viewmodel.dart';
import 'user_form.dart';

class RegisterView extends StatelessWidget {
  const RegisterView({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: UserForm(
        submitLabel: 'Registrarme',
        isLoading: auth.isLoading,
        error: auth.error,
        onSubmit: (input) async {
          final ok = await context.read<AuthViewModel>().register(input);
          if (ok && context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
