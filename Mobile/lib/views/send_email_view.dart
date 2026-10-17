import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/notification.dart';
import '../viewmodels/notification_viewmodel.dart';

class SendEmailView extends StatefulWidget {
  const SendEmailView({super.key});

  @override
  State<SendEmailView> createState() => _SendEmailViewState();
}

class _SendEmailViewState extends State<SendEmailView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await context.read<NotificationViewModel>().send(
      EmailInput(
        email: _email.text.trim(),
        subject: _subject.text.trim(),
        message: _message.text.trim(),
      ),
    );
    if (ok) {
      _subject.clear();
      _message.clear();
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationViewModel>();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Enviar correo')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Correo destino'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: (value) => value == null || !value.contains('@')
                  ? 'Email inválido'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _subject,
              decoration: const InputDecoration(labelText: 'Asunto'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              decoration: const InputDecoration(labelText: 'Mensaje'),
              minLines: 4,
              maxLines: 8,
              validator: _required,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: vm.isSending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Enviar'),
              onPressed: vm.isSending ? null : _submit,
            ),
            const SizedBox(height: 24),
            if (vm.succeeded == true)
              Card(
                color: colors.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.check_circle),
                  title: const Text('Mensaje enviado correctamente.'),
                  subtitle: Text('Pub/Sub · mensaje ${vm.messageId}'),
                ),
              ),
            if (vm.succeeded == false)
              Card(
                color: colors.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error),
                  title: const Text('Error al enviar mensaje.'),
                  subtitle: Text(vm.error ?? ''),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
