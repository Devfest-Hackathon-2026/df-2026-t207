import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app/app.dart';
import 'app/app_loading.dart';
import 'app/demo_mode.dart';
import 'ble/ble_controller.dart';
import 'firebase_options.dart';
import 'services/firebase_auth_service.dart';
import 'settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final darkMode = await loadDarkMode().catchError((Object _) => false);
  demoMode.value = await loadDemoMode(fallback: demoMode.value)
      .catchError((Object _) => demoMode.value);
  demoMode.addListener(() => saveDemoMode(demoMode.value));
  runApp(_AppBootstrap(darkMode: darkMode));
}

Future<DfHackApp> _initializeApp(bool darkMode) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final auth = await FirebaseAuthService.create();
  final api = ApiClient(idToken: auth.idToken);
  return DfHackApp(
    auth: auth,
    api: api,
    ble: BleController.platform(),
    initialDarkMode: darkMode,
    onSaveDarkMode: saveDarkMode,
  );
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap({required this.darkMode});

  final bool darkMode;

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late var _app = _initializeApp(widget.darkMode);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DfHackApp>(
      future: _app,
      builder: (context, snapshot) {
        if (snapshot.data case final app?) return app;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          darkTheme: ThemeData.dark(),
          themeMode: widget.darkMode ? ThemeMode.dark : ThemeMode.light,
          home: snapshot.hasError
              ? Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('アプリを起動できませんでした'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => setState(
                            () => _app = _initializeApp(widget.darkMode),
                          ),
                          child: const Text('もう一度試す'),
                        ),
                      ],
                    ),
                  ),
                )
              : const AppLoadingScreen(),
        );
      },
    );
  }
}
