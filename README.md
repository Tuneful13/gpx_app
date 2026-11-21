# gpx_app

App Android (Flutter) para seguir rutas GPX por el monte: mapa con la ruta, perfil de altitud,
guiado por voz y avisos si te sales del camino. Funciona sin cobertura con mapas offline.

## Estado actual

- **Versión 1.0.0** publicada como release (APK Android) el 21/11/2026.
- 146 tests pasan y el análisis de código no da avisos.
- **Lo siguiente es probarla en el móvil en una ruta real**, sobre todo los mapas offline.

## Lo que ya tiene

**Rutas**
- Abrir archivos GPX (track, ruta y puntos de interés).
- Estadísticas: distancia, desnivel positivo y negativo, altitud mínima y máxima, duración.
- Perfil de altitud.

**Navegación**
- Posición GPS en el mapa con flecha de dirección y mapa orientado hacia donde vas.
- El GPS sigue funcionando con la pantalla apagada (notificación en primer plano).
- Guiado por voz: próximos giros, puntos de interés, aviso por kilómetro y llegada al final.
- Aviso de desvío con sonido, vibración y voz, y umbral de distancia configurable.
- Pantalla siempre encendida opcional.
- Modo simulación para probar una ruta sin moverte (tres velocidades).

**Mapas**
- Mapa online de OpenStreetMap cuando no hay mapas descargados.
- Mapas offline por zonas (Cantabria, La Rioja, País Vasco, Navarra, Pirineo aragonés, Pirineo
  catalán, Andorra y Pirineo francés), con curvas de nivel cada 10 m opcionales.
- Descarga con progreso, reanudación si se corta, actualización y borrado
  (Ajustes > Mapas > Mapas offline).
- Las zonas descargadas se combinan en un único mapa. Usa MapLibre (`maplibre_gl` 0.27).
- Los mapas se generan en el repositorio aparte
  [mapas-norte-pirineos](https://github.com/Tuneful13/mapas-norte-pirineos).

**Ajustes**
- Voz (velocidad, voz concreta, activada al empezar), sonido de aviso a elegir y vibración,
  con botones para probar cada uno.
- Opción para restablecer los valores de fábrica. Los ajustes se guardan entre sesiones.

## Lo que falta

**Antes de usarla en serio**
- [ ] Probar en el móvil en una ruta real: GPS, voz, avisos y batería.
- [ ] Probar los mapas offline en el móvil: descarga, uso sin cobertura y curvas de nivel.

**Mejoras previstas**
- [ ] Descarga en segundo plano. Ahora solo descarga con la app abierta y, si el sistema la
      cierra, se reanuda al volver a pulsar descargar.
- [ ] Descargar solo la zona del GPX: extraer del mapa grande el área alrededor de la ruta
      (PMTiles permite pedir trozos por HTTP).
- [ ] Compartir o exportar rutas (la dependencia `share_plus` está instalada pero sin usar).

**Si algún día se publica**
- [ ] Firma propia para la release (ahora usa la firma de depuración).
- [ ] Nombre, icono y descripción definitivos.

## Compilar

```bash
flutter test
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```
