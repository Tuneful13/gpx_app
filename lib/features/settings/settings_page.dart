import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../map/offline_maps.dart';
import '../map/offline_maps_page.dart';
import '../navigation/alert_player.dart';
import '../navigation/speaker.dart';
import 'alert_sound.dart';
import 'app_settings.dart';
import 'settings_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _speak(WidgetRef ref, AppSettings s, String text) {
    return ref.read(speakerProvider).speak(
          text,
          rate: s.voiceRate,
          voiceName: s.voiceName,
          voiceLocale: s.voiceLocale,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final voices = ref.watch(voicesProvider).asData?.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        actions: [
          IconButton(
            tooltip: 'Restablecer valores',
            icon: const Icon(Icons.restore),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('¿Restablecer los ajustes?'),
                  content: const Text('Todos los valores volverán a los de fábrica.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Restablecer'),
                    ),
                  ],
                ),
              );
              if (ok == true) controller.reset();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // --- Pantalla (arriba del todo) ---
          const _Section('Pantalla'),
          SwitchListTile(
            title: const Text('Mantener la pantalla encendida'),
            subtitle: const Text('Mientras sigues una ruta. Gasta más batería.'),
            value: s.keepScreenOn,
            onChanged: (v) => controller.update((c) => c.copyWith(keepScreenOn: v)),
          ),
          const Divider(),

          // --- Aviso de salida de ruta ---
          const _Section('Aviso de salida de ruta'),
          _SliderTile(
            title: 'Umbral de desvío',
            subtitle: 'Distancia a la ruta a partir de la cual se avisa de que '
                'te has salido. Más bajo = avisa antes, pero con más falsas '
                'alarmas por el ruido del GPS.',
            value: s.offRouteThresholdM,
            min: AppSettings.minOffRouteThresholdM,
            max: AppSettings.maxOffRouteThresholdM,
            step: 5,
            format: (v) => '${v.round()} m',
            onChanged: (v) =>
                controller.update((c) => c.copyWith(offRouteThresholdM: v)),
          ),
          _SliderTile(
            title: 'Repetir aviso cada',
            subtitle: 'Cada cuánto se repite el aviso mientras sigues fuera de la ruta.',
            value: s.offRouteRepeatSeconds.toDouble(),
            min: AppSettings.minOffRouteRepeatSeconds.toDouble(),
            max: AppSettings.maxOffRouteRepeatSeconds.toDouble(),
            step: 5,
            format: (v) => '${v.round()} s',
            onChanged: (v) =>
                controller.update((c) => c.copyWith(offRouteRepeatSeconds: v.round())),
          ),
          SwitchListTile(
            title: const Text('Sonido'),
            subtitle: const Text('Reproduce un sonido al salirte de la ruta.'),
            value: s.alertSoundEnabled,
            onChanged: (v) =>
                controller.update((c) => c.copyWith(alertSoundEnabled: v)),
          ),
          if (s.alertSoundEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<AlertSound>(
                      key: const ValueKey('sound-picker'),
                      showSelectedIcon: false,
                      segments: [
                        for (final a in AlertSound.values)
                          ButtonSegment(value: a, label: Text(a.label)),
                      ],
                      selected: {s.alertSound},
                      onSelectionChanged: (sel) {
                        controller.update((c) => c.copyWith(alertSound: sel.first));
                        // Al elegir un sonido se oye, para comparar rápido.
                        ref.read(alertPlayerProvider).sound(sel.first);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const ValueKey('test-sound'),
                    tooltip: 'Probar sonido',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => ref.read(alertPlayerProvider).sound(s.alertSound),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            title: const Text('Vibración'),
            subtitle: const Text('Vibra al salirte de la ruta (solo en móvil).'),
            value: s.alertVibrationEnabled,
            secondary: IconButton(
              key: const ValueKey('test-vibration'),
              tooltip: 'Probar vibración',
              icon: const Icon(Icons.vibration),
              onPressed: () => ref.read(alertPlayerProvider).vibrate(),
            ),
            onChanged: (v) =>
                controller.update((c) => c.copyWith(alertVibrationEnabled: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('test-full'),
                icon: const Icon(Icons.notifications_active),
                label: const Text('Probar aviso completo'),
                onPressed: () {
                  // Igual que en una ruta real: voz (si está activada) + sonido + vibración.
                  if (s.voiceEnabled) _speak(ref, s, 'Te has salido de la ruta');
                  playAlarm(s, ref.read(alertPlayerProvider));
                },
              ),
            ),
          ),
          const Divider(),

          // --- Guía por voz ---
          const _Section('Guía por voz'),
          SwitchListTile(
            title: const Text('Voz activada al empezar'),
            subtitle: const Text('Podrás silenciarla durante la ruta.'),
            value: s.voiceEnabled,
            onChanged: (v) => controller.update((c) => c.copyWith(voiceEnabled: v)),
          ),
          _SliderTile(
            title: 'Velocidad de la voz',
            subtitle: '100 % es la velocidad normal.',
            value: s.voiceRate,
            min: AppSettings.minVoiceRate,
            max: AppSettings.maxVoiceRate,
            step: 0.05,
            format: (v) => '${(v / AppSettings.defaultVoiceRate * 100).round()} %',
            onChanged: (v) => controller.update((c) => c.copyWith(voiceRate: v)),
          ),
          if (voices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      key: const ValueKey('voice-picker'),
                      isExpanded: true,
                      value: voices.any((v) => v.name == s.voiceName)
                          ? s.voiceName
                          : '',
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Automática (la mejor disponible)'),
                        ),
                        for (final v in voices)
                          DropdownMenuItem(
                            value: v.name,
                            child: Text(v.label, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (name) {
                        if (name == null) return;
                        final match = voices.where((v) => v.name == name);
                        controller.update(
                          (c) => c.copyWith(
                            voiceName: name,
                            voiceLocale: match.isEmpty ? '' : match.first.locale,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('test-voice'),
                icon: const Icon(Icons.record_voice_over),
                label: const Text('Probar voz'),
                onPressed: () => _speak(
                  ref,
                  s,
                  'En ${spokenDistance(s.turnAnnounceM)}, gira a la derecha',
                ),
              ),
            ),
          ),
          _SliderTile(
            title: 'Aviso previo de giro',
            subtitle: 'A cuántos metros de un giro se da el primer aviso.',
            value: s.turnAnnounceM,
            min: AppSettings.minTurnAnnounceM,
            max: AppSettings.maxTurnAnnounceM,
            step: 10,
            format: (v) => '${v.round()} m',
            onChanged: (v) => controller.update((c) => c.copyWith(turnAnnounceM: v)),
          ),
          _SliderTile(
            title: 'Sensibilidad de giros',
            subtitle: 'Cambio de dirección mínimo para avisar. Más bajo = avisa '
                'también de giros suaves; más alto = solo giros marcados.',
            value: s.turnMinAngleDeg,
            min: AppSettings.minTurnMinAngleDeg,
            max: AppSettings.maxTurnMinAngleDeg,
            step: 5,
            format: (v) => '${v.round()}°',
            onChanged: (v) => controller.update((c) => c.copyWith(turnMinAngleDeg: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Los cambios se aplican al iniciar la siguiente ruta.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 32),

          // --- Mapas offline (abajo: se tocan poco) ---
          const _Section('Mapas'),
          ListTile(
            key: const ValueKey('open-offline-maps'),
            leading: const Icon(Icons.download_for_offline),
            title: const Text('Mapas offline'),
            subtitle: Text(switch (ref.watch(offlineMapsProvider).asData?.value) {
              final m? when m.regions.isNotEmpty =>
                '${m.regions.length} ${m.regions.length == 1 ? 'zona descargada' : 'zonas descargadas'}'
                    ' · ${formatBytes(m.totalBytes)}',
              _ => 'Descarga mapas por zonas para usarlos sin conexión',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OfflineMapsPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final double step;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
              Text(
                format(value),
                key: ValueKey('value-$title'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
          Text(subtitle, style: theme.textTheme.bodySmall),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            label: format(value),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
