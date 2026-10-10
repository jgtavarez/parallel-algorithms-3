import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../repositories/file_repository.dart';
import '../repositories/user_repository.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/dashboard_viewmodel.dart';
import '../viewmodels/gallery_viewmodel.dart';
import '../viewmodels/users_viewmodel.dart';
import 'gallery_view.dart';
import 'users_view.dart';
import 'widgets.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (context.mounted) {
      context.read<DashboardViewModel>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final profile = vm.profile;
    final stats = vm.stats;
    final loadTime = vm.loadTime;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthViewModel>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Carga concurrente · Future.wait',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text('3 peticiones lanzadas al mismo tiempo'),
                    if (loadTime != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _Metric(
                              'Tiempo total',
                              formatDuration(loadTime),
                            ),
                          ),
                          Expanded(
                            child: _Metric(
                              'Suma de las 3',
                              formatDuration(vm.sumOfRequests),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (vm.isLoading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            if (vm.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  vm.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            _RequestSection(
              endpoint: 'GET /profile',
              time: vm.requestTimes['GET /profile'],
              child: profile == null
                  ? const SizedBox.shrink()
                  : ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(user: profile, radius: 24),
                      title: Text('Hola, ${profile.firstName}'),
                      subtitle: Text(profile.email),
                    ),
            ),
            _RequestSection(
              endpoint: 'GET /stats',
              time: vm.requestTimes['GET /stats'],
              child: stats == null
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        Expanded(
                          child: _StatTile('Usuarios', '${stats.totalUsers}'),
                        ),
                        Expanded(
                          child: _StatTile('Archivos', '${stats.totalFiles}'),
                        ),
                      ],
                    ),
            ),
            _RequestSection(
              endpoint: 'GET /users',
              time: vm.requestTimes['GET /users'],
              child: Column(
                children: [
                  for (final user in vm.users.take(3))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: UserAvatar(user: user, radius: 16),
                      title: Text(user.fullName),
                      subtitle: Text(user.email),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.people),
                      label: Text('Ver los ${vm.users.length} usuarios'),
                      onPressed: () => _open(
                        context,
                        ChangeNotifierProvider(
                          create: (context) => UsersViewModel(
                            context.read<UserRepository>(),
                            context.read<FileRepository>(),
                          )..load(),
                          child: const UsersView(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Galería'),
              onPressed: () => _open(
                context,
                ChangeNotifierProvider(
                  create: (context) =>
                      GalleryViewModel(context.read<FileRepository>())
                        ..loadFiles(),
                  child: const GalleryView(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({
    required this.endpoint,
    required this.time,
    required this.child,
  });

  final String endpoint;
  final Duration? time;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final time = this.time;
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                endpoint,
                style: labelStyle?.copyWith(fontFamily: 'monospace'),
              ),
              const Spacer(),
              if (time != null) Text(formatDuration(time), style: labelStyle),
            ],
          ),
          const Divider(),
          child,
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
