import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/ads.dart';
import 'core/android_tv/box_client.dart';
import 'core/storage.dart';
import 'core/tv_client.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = TVClient(storage: const DeviceStorage());
  client.webFocusScript = await rootBundle.loadString('assets/web_focus.js');
  client.videoDiscoveryScript = await rootBundle.loadString(
    'assets/web_video.js',
  );
  await client.initialize();
  final box = BoxClient(storage: const DeviceStorage());
  await box.initialize();
  BoxClient.shared = box;
  box.onCommandError = client.reportError;
  client.keyRouter = (name) => box.route(name, client.foreground);
  runApp(RemoteApp(client: client));
  Ads.shared.start();
  if (client.selected != null) unawaited(client.connect(client.selected!));
}

class RemoteApp extends StatelessWidget {
  const RemoteApp({super.key, required this.client});
  final TVClient client;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kumanda',
    debugShowCheckedModeBanner: false,
    locale: const Locale('tr'),
    supportedLocales: const [Locale('tr'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff941f45),
        brightness: Brightness.light,
        surface: const Color(0xfff2f2f7),
      ),
      scaffoldBackgroundColor: const Color(0xfff2f2f7),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    home: RemoteShell(client: client),
  );
}
