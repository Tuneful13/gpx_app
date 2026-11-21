import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'features/routes/viewer_page.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SettingsStore store;
  try {
    await Hive.initFlutter();
    store = HiveSettingsStore(await Hive.openBox<dynamic>('settings'));
  } catch (e) {
    // Si falla el disco la app sigue funcionando, solo que sin recordar ajustes.
    debugPrint('No se pudo abrir el almacenamiento de ajustes: $e');
    store = MemorySettingsStore();
  }

  runApp(ProviderScope(
    overrides: [settingsStoreProvider.overrideWithValue(store)],
    child: const GpxApp(),
  ));
}

class GpxApp extends StatelessWidget {
  const GpxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPX App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ViewerPage(),
    );
  }
}
