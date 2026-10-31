import 'package:flutter/material.dart';
import 'core/db.dart';
import 'core/ui.dart';
import 'screens/gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  themeMode.value = (await Db.setting('dark')) == '1' ? ThemeMode.dark : ThemeMode.light;
  runApp(const SmartStoreHubApp());
}

class SmartStoreHubApp extends StatelessWidget {
  const SmartStoreHubApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (c, m, _) => MaterialApp(
          title: 'SmartStoreHub',
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          darkTheme: appTheme(Brightness.dark),
          themeMode: m,
          home: const Gate(),
        ),
      );
}
