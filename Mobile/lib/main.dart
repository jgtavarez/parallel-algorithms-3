import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'repositories/auth_repository.dart';
import 'repositories/dashboard_repository.dart';
import 'repositories/file_repository.dart';
import 'repositories/user_repository.dart';
import 'services/api_service.dart';
import 'services/session_service.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/dashboard_viewmodel.dart';
import 'views/dashboard_view.dart';
import 'views/login_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionService();
  final api = ApiService(session);

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => UserRepository(api)),
        Provider(create: (_) => FileRepository(api)),
        Provider(create: (_) => DashboardRepository(api)),
        ChangeNotifierProvider(
          create: (_) =>
              AuthViewModel(AuthRepository(api, session))..restoreSession(),
        ),
      ],
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthViewModel>().status;
    return MaterialApp(
      title: 'Integrador',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: switch (status) {
        AuthStatus.unknown => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        AuthStatus.loggedOut => const LoginView(),
        AuthStatus.loggedIn => ChangeNotifierProvider(
          create: (context) => DashboardViewModel(
            context.read<DashboardRepository>(),
            context.read<UserRepository>(),
          )..load(),
          child: const DashboardView(),
        ),
      },
    );
  }
}
