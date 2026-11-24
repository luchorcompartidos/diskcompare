# DESARROLLO — DiskCompare

> Archivo para retomar el trabajo en un chat nuevo.
> Uso: *"Seguimos con DiskCompare, etapa 2. Leé `DESARROLLO.md` del repo luchorcompartidos/diskcompare."*
> Mantenerlo corto (idealmente menos de 1 página). Lo viejo va resumido en "Historial".

---

## 1. Ficha rápida
| Campo | Valor |
|---|---|
| App | DiskCompare |
| Repo | luchorcompartidos/diskcompare |
| URL publicada | — (APK en Releases) |
| Tipo | Android APK (Flutter): 2 APK por Release — `arm64-v8a` (Android 7+) y `android5-6-armeabi-v7a` (Android 5/6) |
| Estado | Prototipo |
| Última versión (Release) | v0.0.3 — 2026-11-24 |
| Se conecta con | ninguno (Etapa 2: carpeta compartida de Windows por SMB) |

## 2. Etapa actual
**Etapa 1 — Análisis del almacenamiento del celular**
- Objetivo de la etapa: un Disk Usage + TreeSize para Android, solo lectura.
- Hecho hasta ahora: escaneo en segundo plano (interno y SD); pestañas Árbol, Mapa, Grandes y Tipos; detalle de archivo; aviso de lo que Android no deja ver.
- v0.0.2: mapa con zoom (pellizcar) y arrastre, detalle con presión larga, bloque gris abre los elementos chicos; corregido que la barra de navegación de Android tapaba la parte de abajo.
- v0.0.3: dos APK por Release: normal solo arm64-v8a (~17 MB, antes 46 MB) y uno para Android 5 y 6 solo armeabi-v7a (Flutter 3.32). La versión y la arquitectura se ven en la app (Acerca de y pie del inicio).
- En curso: probar la v0.0.3 en el celular y en las 2 tablets (desinstalar antes la v0.0.1 si sigue instalada). Desde la v0.0.2 las versiones nuevas se instalan encima.

## 3. Próximos pasos
1. Probar la v0.0.3 (celular + tablets Android 6.0.1 y Bangho AERO J1216 Android 5.0) y anotar ajustes (Patch).
2. Etapa 2: comparar contra una carpeta compartida de Windows por WiFi (SMB, parte nativa en Kotlin con smbj): solo en el celular / solo en la PC / en ambos / con diferencias.
3. Etapa 2b (opcional): indexador en la PC (.exe Flutter o script) que se corre a pedido y le pasa la lista a la app, para no leer todo por WiFi.

## 4. Decisiones tomadas
- 2026-11-23 App nueva (no módulo de Multi G-DRIVE ni de FotosCompare).
- 2026-11-24 Flutter — mismo ecosistema que Multi G-DRIVE/Reproductor; habilita indexador o versión Windows del mismo código.
- 2026-11-24 Etapa 1 sola en este paso, para no encarecer; Release Patch.
- 2026-11-24 Firma fija con los mismos Secrets de Notas/Multi G-DRIVE (desde v0.0.2; la v0.0.1 usó clave de prueba y hay que desinstalarla una vez).
- 2026-11-24 Dos APK por Release (decidido en v0.0.3, antes había un APK universal de 46 MB):
  - Normal `diskcompare-vX.Y.Z-arm64-v8a.apk`: **arm64-v8a**, último Flutter, Android 7+ (celulares de los últimos 6–8 años).
  - Tablets viejas `diskcompare-vX.Y.Z-android5-6-armeabi-v7a.apk`: **armeabi-v7a**, Flutter 3.32 (el último que soporta Android 5/6; desde Flutter 3.35 el mínimo es Android 7). También sirve a celulares con Android de 32 bits.
  - Sin x86_64: no hay equipos que lo necesiten (no afecta a una futura versión Windows, que es otra compilación).
  - Tablet Bangho AERO J1216 (Intel Atom Z3735F, Android 5.0): kernel x86_64 pero conjuntos de instrucciones `x86 armeabi-v7a armeabi` → Android de 32 bits; usa armeabi-v7a con el traductor de Intel (Houdini). Puede ir más lenta; si la app se cerrara al abrir, la alternativa sería una versión nativa Kotlin solo para esa tablet.
  - Los nombres de los APK y el texto de cada Release llevan el nombre literal de la arquitectura.
- Sin borrado automático: cualquier acción futura se marca, se revisa y se confirma.

## 5. Pendientes / dudas abiertas
- [ ] Aviso de versión nueva y Changelog leyendo las Releases (como `updates.dart` de multigdrive), según ESTANDAR-VERSIONES.md.
- [ ] Guardar el último escaneo (hoy se pierde al cerrar la app); lo necesita la Etapa 2.
- [ ] Ícono propio de la app.
- [ ] Confirmar que la app abre y escanea en la Bangho (traductor de Intel).
- [ ] Si alguna función futura necesita algo más nuevo que Flutter 3.32, decidir si se excluye del APK android5-6.
- [ ] Alta en Mi Panel y en la caja de apps (mapa-apps.md).

## 6. Datos técnicos clave
- Archivos principales: `lib/main.dart` (inicio, permisos, volúmenes), `lib/scanner.dart` (escaneo en isolate), `lib/results.dart` (pestañas), `lib/treemap.dart` (mapa), `lib/format.dart` (tamaños y tipos).
- Nativo: `tool/patch_platforms.py` escribe `MainActivity.kt` (canal `dc/storage`: `sdk`, `volumes`) y agrega los permisos al manifest. La carpeta `android/` no se versiona: la genera `flutter create` en Actions.
- Cómo se publica: push a main → GitHub Actions (`ci.yml`, matriz `normal` / `android5-6`) compila los 2 APK, firmados con los Secrets ANDROID_KEYSTORE_BASE64 / _PASSWORD / ANDROID_KEY_ALIAS → Release con los 2 .apk y una tabla "¿Qué archivo bajar?".
- `--dart-define=APP_ABI` muestra la arquitectura en la app; el código tiene que seguir compilando con Flutter 3.32 (no usar APIs más nuevas sin revisar el APK android5-6).
- Releases: según `ESTANDAR-VERSIONES.md` del repo home (`[major]` / `[minor]` / `[patch]` / `[skip release]` en el commit; cambios que no tocan la app van sin release)

## 7. Historial (resumido)
- v0.0.3 2026-11-24 — Dos APK: arm64-v8a (Android 7+) y android5-6-armeabi-v7a (Android 5/6).
- v0.0.2 2026-11-24 — Mapa: zoom, arrastre, detalle con presión larga, elementos chicos; barra de navegación ya no tapa la app.
- v0.0.1 2026-11-24 — Etapa 1: escaneo, Árbol, Mapa, Grandes y Tipos.

---
*Al cerrar cada sesión: actualizar secciones 1, 2, 3 y 7, y subir el archivo al repo.*
