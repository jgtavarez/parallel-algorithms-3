import 'package:flutter/material.dart';

import '../models/user.dart';

// Shared by register, create user and edit user.
class UserForm extends StatefulWidget {
  const UserForm({
    super.key,
    required this.submitLabel,
    required this.isLoading,
    required this.onSubmit,
    this.user,
    this.error,
  });

  final User? user;
  final String submitLabel;
  final bool isLoading;
  final String? error;
  final Future<void> Function(UserInput input) onSubmit;

  @override
  State<UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<UserForm> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName = TextEditingController(text: widget.user?.firstName);
  late final _lastName = TextEditingController(text: widget.user?.lastName);
  late final _email = TextEditingController(text: widget.user?.email);
  final _password = TextEditingController();

  bool get _isEditing => widget.user != null;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(
      UserInput(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextFormField(
            controller: _firstName,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lastName,
            decoration: const InputDecoration(labelText: 'Apellido'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            validator: (value) =>
                value == null || !value.contains('@') ? 'Email inválido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            decoration: InputDecoration(
              labelText: _isEditing
                  ? 'Nueva contraseña (opcional)'
                  : 'Contraseña',
            ),
            obscureText: true,
            validator: (value) {
              if (_isEditing && (value == null || value.isEmpty)) return null;
              return value == null || value.length < 6
                  ? 'Mínimo 6 caracteres'
                  : null;
            },
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.isLoading ? null : _submit,
            child: widget.isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
