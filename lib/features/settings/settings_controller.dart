import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';
import 'settings_store.dart';

/// En `main` se sustituye por el almacenamiento en disco (Hive).
final settingsStoreProvider =
    Provider<SettingsStore>((ref) => MemorySettingsStore());

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() =>
      AppSettings.fromMap(ref.read(settingsStoreProvider).load());

  void update(AppSettings Function(AppSettings current) change) {
    final next = change(state);
    if (next == state) return;
    state = next;
    ref.read(settingsStoreProvider).save(next.toMap());
  }

  void reset() => update((_) => const AppSettings());
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
