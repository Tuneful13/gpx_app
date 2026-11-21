# gpx_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Pendiente / futuro

- **Mapas vectoriales offline por zonas (integrado, falta probar en el móvil):** Cantabria,
  La Rioja, País Vasco, Navarra, Pirineo aragonés, Pirineo catalán, Andorra y Pirineo francés, cada
  una con mapa base (OSM) y curvas de nivel cada 10 m (Copernicus) opcionales. Se generan y publican
  en el repositorio aparte [mapas-norte-pirineos](https://github.com/Tuneful13/mapas-norte-pirineos);
  la app lee su `catalogo.json` y las descarga en Ajustes > Mapas > Mapas offline (con progreso,
  reanudación si se corta, actualización y borrado). El mapa combina todas las zonas descargadas;
  sin ninguna se usa el mapa online de OSM. Usa MapLibre (`maplibre_gl` 0.27, la última compatible
  con Flutter 3.38). Todo lo del mapa está en `lib/features/map/`.
- **Descarga en segundo plano:** ahora la descarga sigue mientras la app está abierta; si el sistema
  la cierra, se reanuda al volver a pulsar descargar.
- **Descargar solo la zona del GPX (futuro):** extraer del mapa grande solo el área alrededor de la
  ruta (PMTiles permite pedir trozos por HTTP).
