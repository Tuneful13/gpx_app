import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Rotación del mapa para que la dirección de marcha [headingDeg] quede hacia
/// arriba (como Maps al navegar). Un mapa girado +r grados en sentido horario
/// deja el norte a r grados de la vertical, así que hay que girar -heading.
double headingUpRotation(double headingDeg) {
  final r = (-headingDeg) % 360; // en [0, 360)
  return r > 180 ? r - 360 : r;
}

/// Convierte la rotación del mapa (grados, horario) en el "bearing" de
/// MapLibre: el rumbo de la brújula que queda arriba de la pantalla.
double rotationToBearing(double rotationDeg) => (-rotationDeg) % 360;

/// Estado deseado de la cámara del mapa, independiente de la librería.
///
/// La app pide movimientos con [move] / [moveAndRotate]; el widget del mapa
/// escucha y los aplica al mapa nativo. Cuando es el usuario quien mueve el
/// mapa, el widget informa con [syncFromMap] (sin volver a mover nada).
/// Al no depender del mapa nativo, se puede probar en tests.
class MapViewController extends ChangeNotifier {
  MapViewController({this.zoom = 14});

  LatLng? center;
  double zoom;

  /// Grados, sentido horario (0 = norte arriba). Ver [headingUpRotation].
  double rotation = 0;

  double get bearing => rotationToBearing(rotation);

  /// Centra en [c] sin cambiar la orientación.
  void move(LatLng c, double z) {
    center = c;
    zoom = z;
    notifyListeners();
  }

  /// Centra en [c] y gira el mapa [rotationDeg] grados.
  void moveAndRotate(LatLng c, double z, double rotationDeg) {
    center = c;
    zoom = z;
    rotation = rotationDeg;
    notifyListeners();
  }

  /// Lo llama el mapa cuando su cámara cambia (p. ej. el usuario lo mueve).
  void syncFromMap(LatLng c, double z, double bearingDeg) {
    center = c;
    zoom = z;
    final r = (-bearingDeg) % 360;
    rotation = r > 180 ? r - 360 : r;
  }
}
