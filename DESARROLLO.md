# DESARROLLO — DiskCompare

> Archivo para retomar el trabajo en un chat nuevo.
> Uso: *"Seguimos con DiskCompare, etapa 2. Leé `DESARROLLO.md` del repo luchorcompartidos/diskcompare."*
> Mantenerlo corto (idealmente menos de 1 página). Lo viejo va resumido en "Historial".
> Dispositivos viejos (**Sí**): al cerrar cada etapa, revisar si lo hecho deja algo nuevo para `plantilla/APK-DISPOSITIVOS-VIEJOS.md` del repo home y, si corresponde, actualizarla (secciones 3–5 + Historial) y subirla. No hace falta que el usuario lo pida.

---

## 1. Ficha rápida
| Campo | Valor |
|---|---|
| App | DiskCompare |
| Repo | luchorcompartidos/diskcompare |
| URL publicada | — (APK en Releases; acceso en Mi Panel con `github-apk:luchorcompartidos/diskcompare`) |
| Tipo | Android APK (Flutter): 2 APK por Release — `arm64-v8a` (Android 7+) y `android5-6-armeabi-v7a` (Android 5/6) |
| Estado | Prototipo |
| Última versión (Release) | v0.0.6 — 2026-11-24 |
| Dispositivos viejos (Android 5/6) | **Sí** — aplicar `plantilla/APK-DISPOSITIVOS-VIEJOS.md` (repo home) en cada cambio y, al cerrar cada etapa, revisar si lo hecho deja algo nuevo para esa guía (un problema, un arreglo, una versión de biblioteca, una prueba en las tablets) y, si corresponde, actualizarla (sección del tema + Historial) y subirla al repo home |
| Se conecta con | carpeta compartida de Windows por SMB 2/3 (smbj), solo lectura |

## 2. Etapa actual
**Etapa 2 — Comparar contra una carpeta compartida de Windows** (Etapa 1 cerrada en v0.0.3)
- Objetivo: una carpeta del celular contra `\\PC\Compartida\sub` por WiFi, solo lectura.
- v0.0.4 (hecho): pantalla *Comparar con la PC* (carpeta del celular + carpeta de la PC, usuario y contraseña de Windows, explorador de carpetas de la PC); resultado en 4 pestañas: **Solo celular / Solo PC / En ambos / Diferencias**, con detalle de rutas, tamaños y fechas; ver la PC con Árbol/Mapa; el último análisis de cada volumen queda guardado.
- v0.0.5: aviso de versión nueva (tarjeta en el inicio con **Descargar**, baja el APK de la misma arquitectura) y Changelog leyendo las Releases (botón ⓘ o pie del inicio). Alta en el mapa de la caja de apps.
- v0.0.6: resultado con **buscador** (nombre o carpeta) y **filtro por tipo** en las 4 pestañas; **exportar CSV** (pestaña actual o las 4, con los filtros aplicados) a `Descargas/DiskCompare` o con **Compartir**; opción **Comparar también por carpeta** (en la pantalla de comparar y en el menú ⋮ del resultado, sin volver a leer).
- En curso: probar la v0.0.4 a v0.0.6 contra la PC (celular + 2 tablets). Es la primera versión con smbj: si el CI o la app fallan, revisar primero la sección 6 (parte nativa).

## 3. Próximos pasos
1. Probar la v0.0.4: conexión por IP y por nombre (`NOMBRE-PC` / `NOMBRE-PC.local`), usuario local y cuenta Microsoft, carpeta grande (tiempo de lectura por WiFi), y en las tablets Android 5/6. Anotar ajustes (Patch).
2. Probar la v0.0.6: exportar CSV (guardar y compartir) en el celular y en las 2 tablets; abrir el CSV en Excel/Sheets (acentos y columnas); buscador con muchas filas en la tablet.
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
- 2026-11-24 Etapa 2 completa en un solo paso (v0.0.4, Patch).
- 2026-11-24 Criterio de "iguales": **solo nombre (sin distinguir mayúsculas) + tamaño**, sin importar la carpeta (encuentra copias movidas). Mismo nombre con otro tamaño → *Diferencias*.
- 2026-11-24 Contraseña de Windows: se guarda **cifrada** en el equipo (Android Keystore: AES-GCM en Android 6+, RSA en Android 5), con opción "Olvidar". Sin plugins (nativo en `Secret.kt`) para no depender de versiones que pidan Android 6+.
- 2026-11-24 Aviso de versión y Changelog según `ESTANDAR-VERSIONES.md`, como `updates.dart` de multigdrive pero sin paquetes (`dart:io` + canal nativo `openUrl`) para seguir compilando con Flutter 3.32. Sin conexión usa la copia `releases.json`. Del texto de cada Release se muestra solo la sección "Cambios".
- 2026-11-24 Exportar CSV: las dos opciones, guardar en Descargas y compartir (v0.0.6). Separador `;`, UTF-8 con BOM, tamaños en bytes, fechas dd/mm/aaaa; una fila por archivo con columna "Resultado".
- 2026-11-24 Comparar por carpeta: misma ruta relativa (sin distinguir mayúsculas) + tamaño; se elige al comparar o en el resultado (se recalcula sin leer de nuevo) y queda guardado en `compare.json`.
- 2026-11-24 SMB con **smbj 0.13.0** (Kotlin nativo, SMB 2/3; Windows 10/11 no usan SMB1). Sin listar las carpetas compartidas del equipo: se escribe `\\PC\Compartida` y desde ahí se explora.

## 5. Pendientes / dudas abiertas
- [ ] Ícono propio de la app.
- [ ] Confirmar que la app abre y escanea en la Bangho (traductor de Intel).
- [ ] Si alguna función futura necesita algo más nuevo que Flutter 3.32, decidir si se excluye del APK android5-6.
- [ ] Mi Panel: pegar la fila de DiskCompare en la pestaña "Accesos" de la Google Sheet (mapa-apps.md ya actualizado el 2026-11-24).
- [ ] Confirmar que smbj conecta en Android 5/6 (tablets) — usa desugaring de Java 8.
- [ ] Si la PC tiene muchos archivos, medir cuánto tarda por WiFi; si es mucho, adelantar la Etapa 2b.

## 6. Datos técnicos clave
- Archivos principales: `lib/main.dart` (inicio, permisos, volúmenes), `lib/scanner.dart` (escaneo en isolate), `lib/results.dart` (pestañas), `lib/treemap.dart` (mapa), `lib/format.dart` (tamaños y tipos).
- Versiones: `lib/updates.dart` (Releases de GitHub, comparación SemVer, APK según `APP_ABI`).
- Dart Etapa 2: `lib/compare.dart` (pantalla, comparación en isolate, selector de carpetas, resultado), `lib/pc.dart` (canales nativos, ajustes `compare.json`, lectura del .tsv de la PC), `lib/store.dart` (escaneos guardados `scan-*.json.gz` en la carpeta privada de la app).
- Nativo: los `.kt` están en `tool/android/` (`MainActivity.kt`, `SmbBridge.kt`, `Secret.kt`, `Export.kt`) y `tool/patch_platforms.py` los copia junto con `proguard-rules.pro`, agrega permisos (INTERNET y archivos) y a `build.gradle.kts` la dependencia smbj + desugaring (`desugar_jdk_libs 2.0.4`). La carpeta `android/` no se versiona: la genera `flutter create` en Actions.
- Exportar (v0.0.6): `tool/android/Export.kt` sin plugins — Android 10+ MediaStore (`Download/DiskCompare`), Android 5–9 carpeta pública Descargas; Compartir con FileProvider (`androidx.core:core:1.13.1`, autoridad `<paquete>.files`, `tool/android/dc_file_paths.xml` → `cache/export`). El CSV se arma en un isolate (`_buildCsv` en `compare.dart`).
- Canales: `dc/storage` (`sdk`, `volumes`, `filesDir`, `cacheDir`, `openUrl`, `secretSave/Load/Delete`, `saveDownload`, `shareFile`) y `dc/smb` (`list`, `scan`, `cancel`; avisa `progress`). El scan de la PC escribe `pc-scan.tsv` (`ruta\ttamaño\tfecha`; `!\truta` = carpeta sin permiso); no recorre enlaces/junctions de Windows.
- Cómo se publica: push a main → GitHub Actions (`ci.yml`, matriz `normal` / `android5-6`) compila los 2 APK, firmados con los Secrets ANDROID_KEYSTORE_BASE64 / _PASSWORD / ANDROID_KEY_ALIAS → Release con los 2 .apk y una tabla "¿Qué archivo bajar?".
- Guía general para otras apps: `plantilla/APK-DISPOSITIVOS-VIEJOS.md` del repo home (sale de este caso).
- `--dart-define=APP_ABI` muestra la arquitectura en la app; el código tiene que seguir compilando con Flutter 3.32 (no usar APIs más nuevas sin revisar el APK android5-6).
- Releases: según `ESTANDAR-VERSIONES.md` del repo home (`[major]` / `[minor]` / `[patch]` / `[skip release]` en el commit; cambios que no tocan la app van sin release)

## 7. Historial (resumido)
- v0.0.6 2026-11-24 — Resultado: buscador, filtro por tipo, exportar CSV (Descargas / Compartir) y comparar por carpeta.
- v0.0.5 2026-11-24 — Aviso de versión nueva y Changelog desde las Releases.
- v0.0.4 2026-11-24 — Etapa 2: comparar con carpeta compartida de Windows (SMB), contraseña cifrada, escaneos guardados.
- v0.0.3 2026-11-24 — Dos APK: arm64-v8a (Android 7+) y android5-6-armeabi-v7a (Android 5/6).
- v0.0.2 2026-11-24 — Mapa: zoom, arrastre, detalle con presión larga, elementos chicos; barra de navegación ya no tapa la app.
- v0.0.1 2026-11-24 — Etapa 1: escaneo, Árbol, Mapa, Grandes y Tipos.

---
*Al cerrar cada sesión: actualizar secciones 1, 2, 3 y 7, y subir el archivo al repo. Revisar también `plantilla/APK-DISPOSITIVOS-VIEJOS.md` (repo home) y actualizarla si corresponde.*
