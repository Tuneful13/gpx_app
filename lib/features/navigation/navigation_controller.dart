import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/screen_on.dart';
import '../routes/route_providers.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import 'alert_player.dart';
import 'guidance_engine.dart';
import 'location_source.dart';
import 'off_route_monitor.dart';
import 'route_matcher.dart';
import 'speaker.dart';
import 'turn_detector.dart';

enum BannerKind { info, warning, success }

class NavBanner {
  const NavBanner(this.text, this.kind);
  final String text;
  final BannerKind kind;
}

class NavState {
  const NavState({
    this.active = false,
    this.loaded,
    this.simulated = false,
    this.position,
    this.headingDeg,
    this.speedMps,
    this.match,
    this.joinedRoute = false,
    this.offRoute = false,
    this.arrived = false,
    this.distanceToRouteM,
    this.doneM = 0,
    this.remainingM = 0,
    this.elapsed = Duration.zero,
    this.eta,
    this.nextTurn,
    this.nextTurnInM,
    this.banner,
    this.muted = false,
    this.accessProblem,
    this.accessIssue,
  });

  final bool active;
  final LoadedRoute? loaded;
  final bool simulated;
  final LatLng? position;
  final double? headingDeg;
  final double? speedMps;
  final MatchResult? match;

  /// Ya has llegado a la ruta alguna vez (antes de eso solo se te guía hacia ella).
  final bool joinedRoute;
  final bool offRoute;
  final bool arrived;
  final double? distanceToRouteM;
  final double doneM;
  final double remainingM;
  final Duration elapsed;
  final Duration? eta;
  final Turn? nextTurn;
  final double? nextTurnInM;
  final NavBanner? banner;
  final bool muted;

  /// Si no se pudo empezar: motivo legible y causa.
  final String? accessProblem;
  final LocationAccess? accessIssue;

  NavState copyWith({
    bool? active,
    bool? simulated,
    LatLng? position,
    double? headingDeg,
    double? speedMps,
    MatchResult? match,
    bool? joinedRoute,
    bool? offRoute,
    bool? arrived,
    double? distanceToRouteM,
    double? doneM,
    double? remainingM,
    Duration? elapsed,
    Duration? eta,
    bool clearEta = false,
    Turn? nextTurn,
    double? nextTurnInM,
    bool clearNextTurn = false,
    NavBanner? banner,
    bool? muted,
  }) {
    return NavState(
      active: active ?? this.active,
      loaded: loaded,
      simulated: simulated ?? this.simulated,
      position: position ?? this.position,
      headingDeg: headingDeg ?? this.headingDeg,
      speedMps: speedMps ?? this.speedMps,
      match: match ?? this.match,
      joinedRoute: joinedRoute ?? this.joinedRoute,
      offRoute: offRoute ?? this.offRoute,
      arrived: arrived ?? this.arrived,
      distanceToRouteM: distanceToRouteM ?? this.distanceToRouteM,
      doneM: doneM ?? this.doneM,
      remainingM: remainingM ?? this.remainingM,
      elapsed: elapsed ?? this.elapsed,
      eta: clearEta ? null : (eta ?? this.eta),
      nextTurn: clearNextTurn ? null : (nextTurn ?? this.nextTurn),
      nextTurnInM: clearNextTurn ? null : (nextTurnInM ?? this.nextTurnInM),
      banner: banner ?? this.banner,
      muted: muted ?? this.muted,
      accessProblem: accessProblem,
      accessIssue: accessIssue,
    );
  }
}

class NavigationController extends Notifier<NavState> {
  StreamSubscription<Fix>? _sub;
  RouteMatcher? _matcher;
  GuidanceEngine? _guidance;
  List<Turn> _turns = const [];
  OffRouteMonitor _monitor = OffRouteMonitor();

  /// Ajustes vigentes al iniciar la ruta. Cambiarlos durante la ruta no la afecta.
  AppSettings _settings = const AppSettings();
  int? _lastSegment;
  DateTime? _startTime;

  @override
  NavState build() {
    ref.onDispose(() => _sub?.cancel());
    return const NavState();
  }

  /// Empieza a seguir [loaded]. [source] permite inyectar una fuente de
  /// posiciones (simulación o pruebas); si no, se usa el GPS real.
  Future<void> start(
    LoadedRoute loaded, {
    LocationSource? source,
    bool simulated = false,
  }) async {
    await stop();

    if (loaded.route.points.length < 2) {
      state = const NavState(
          accessProblem: 'La ruta necesita al menos 2 puntos para navegar.');
      return;
    }

    final LocationSource src = source ?? ref.read(locationSourceProvider);
    final access = await src.ensureAccess();
    if (access != LocationAccess.granted) {
      state = NavState(
        accessProblem: _accessMessage(access),
        accessIssue: access,
      );
      return;
    }

    final settings = ref.read(settingsProvider);
    _settings = settings;
    final matcher = RouteMatcher(loaded.route.points, loaded.stats.cumulativeM);
    _matcher = matcher;
    _turns = detectTurns(
      loaded.route.points,
      loaded.stats.cumulativeM,
      minAngleDeg: settings.turnMinAngleDeg,
    );
    _guidance = GuidanceEngine(
      turns: _turns,
      totalM: matcher.totalM,
      waypoints: loaded.route.waypoints,
      matcher: matcher,
      farAnnounceM: settings.turnAnnounceM,
    );
    _monitor = OffRouteMonitor(
      thresholdM: settings.offRouteThresholdM,
      repeatEvery: Duration(seconds: settings.offRouteRepeatSeconds),
    );
    _lastSegment = null;
    _startTime = null;

    state = NavState(
      active: true,
      loaded: loaded,
      simulated: simulated,
      remainingM: matcher.totalM,
      muted: !settings.voiceEnabled,
      banner: const NavBanner('Buscando tu posición…', BannerKind.info),
    );
    _say('Ruta iniciada. Distancia total ${spokenDistance(matcher.totalM)}');
    if (settings.keepScreenOn) keepScreenOn(true);

    _sub = src.fixes().listen(
      _onFix,
      onError: (Object e) {
        state = state.copyWith(
          banner: const NavBanner(
              'Se ha perdido la señal de GPS', BannerKind.warning),
        );
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _matcher = null;
    _guidance = null;
    if (state.active) {
      keepScreenOn(false);
      await ref.read(speakerProvider).stop();
    }
    state = const NavState();
  }

  void toggleMute() {
    state = state.copyWith(muted: !state.muted);
    if (state.muted) ref.read(speakerProvider).stop();
  }

  void _onFix(Fix fix) {
    final matcher = _matcher;
    final guidance = _guidance;
    if (!state.active || matcher == null || guidance == null) return;

    final m = matcher.match(fix.lat, fix.lon, lastSegment: _lastSegment);
    final dist = m.distanceToRouteM;
    // Solo avanza el "último segmento" si estamos razonablemente cerca, para
    // que tras un desvío largo la búsqueda siga centrada donde ibas.
    if (dist <= _monitor.thresholdM * 2) _lastSegment = m.segment;

    _startTime ??= fix.time;
    final elapsed = fix.time.difference(_startTime!);
    final along = m.alongM;
    final remaining = matcher.totalM - along;

    var banner = state.banner;
    var joined = state.joinedRoute;
    var arrived = state.arrived;
    var offRoute = state.offRoute;

    if (!joined) {
      if (dist <= _monitor.thresholdM) {
        joined = true;
        banner = const NavBanner('Ya estás en la ruta', BannerKind.success);
        _say('Estás en la ruta');
      } else {
        banner = NavBanner(
          'Acércate a la ruta: estás a ${formatDistance(dist)}',
          BannerKind.warning,
        );
      }
    }

    if (joined) {
      final accurateEnough =
          fix.accuracyM == null || fix.accuracyM! <= _monitor.thresholdM;
      if (accurateEnough) {
        switch (_monitor.update(dist, fix.time)) {
          case OffRouteEvent.left:
            _say('Te has salido de la ruta');
            _alarm();
          case OffRouteEvent.stillOff:
            _say('Sigues fuera de la ruta, a ${spokenDistance(dist)}');
            _alarm();
          case OffRouteEvent.returned:
            _say('Has vuelto a la ruta');
            banner = const NavBanner('Has vuelto a la ruta', BannerKind.success);
          case OffRouteEvent.none:
            break;
        }
      }
      offRoute = _monitor.isOff;

      if (offRoute) {
        banner = NavBanner(
          'Fuera de la ruta · a ${formatDistance(dist)}',
          BannerKind.warning,
        );
      } else {
        for (final msg in guidance.update(along)) {
          _say(msg);
          banner = NavBanner(msg, BannerKind.info);
        }
        arrived = guidance.arrived;
        if (arrived) {
          banner =
              const NavBanner('Has llegado al final de la ruta', BannerKind.success);
        }
      }
    }

    Turn? next;
    for (final t in _turns) {
      if (t.alongM - along > 5) {
        next = t;
        break;
      }
    }

    // ETA con la velocidad media desde el inicio (solo con datos suficientes).
    Duration? eta;
    if (joined && elapsed.inSeconds >= 60 && along > 100 && remaining > 0) {
      final avg = along / elapsed.inSeconds;
      eta = Duration(seconds: (remaining / avg).round());
    }

    state = state.copyWith(
      position: LatLng(fix.lat, fix.lon),
      headingDeg: fix.headingDeg,
      speedMps: fix.speedMps,
      match: m,
      joinedRoute: joined,
      offRoute: offRoute,
      arrived: arrived,
      distanceToRouteM: dist,
      doneM: joined ? along : 0,
      remainingM: remaining,
      elapsed: elapsed,
      eta: eta,
      clearEta: eta == null,
      nextTurn: next,
      nextTurnInM: next == null ? null : next.alongM - along,
      clearNextTurn: next == null || !joined,
      banner: banner,
    );
  }

  void _alarm() => playAlarm(_settings, ref.read(alertPlayerProvider));

  void _say(String text) {
    if (state.muted) return;
    ref.read(speakerProvider).speak(
          text,
          rate: _settings.voiceRate,
          voiceName: _settings.voiceName,
          voiceLocale: _settings.voiceLocale,
        );
  }

  static String _accessMessage(LocationAccess a) => switch (a) {
        LocationAccess.serviceDisabled =>
          'El GPS está desactivado. Actívalo para seguir la ruta.',
        LocationAccess.denied =>
          'Necesito permiso de ubicación para seguir la ruta.',
        LocationAccess.deniedForever =>
          'El permiso de ubicación está denegado. Actívalo en los ajustes de la app.',
        LocationAccess.granted => '',
      };
}

final navigationProvider =
    NotifierProvider<NavigationController, NavState>(NavigationController.new);
