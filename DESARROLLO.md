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
| Tipo | Android APK (Flutter) |
| Estado | Prototipo |
| Última versión (Release) | v0.0.2 — 2026-11-24 |
| Se conecta con | ninguno (Etapa 2: carpeta compartida de Windows por SMB) |

## 2. Etapa actual
**Etapa 1 — Análisis del almacenamiento del celular**
- Objetivo de la etapa: un Disk Usage + TreeSize para Android, solo lectura.
- Hecho hasta ahora: escaneo en segundo plano (interno y SD); pestañas Árbol, Mapa, Grandes y Tipos; detalle de archivo; aviso de lo que Android no deja ver.
- v0.0.2: mapa con zoom (pellizcar) y arrastre, detalle con presión larga, bloque gris abre los elementos chicos; corregido que la barra de navegación de Android tapaba la parte de abajo.
- En curso: probar la v0.0.2 en el celular (desinstalar antes la v0.0.1). Desde la v0.0.2 las versiones nuevas se instalan encima.

## 3. Próximos pasos
1. Probar la v0.0.2 y anotar ajustes (Patch).
2. Etapa 2: comparar contra una carpeta compartida de Windows por WiFi (SMB, parte nativa en Kotlin con smbj): solo en el celular / solo en la PC / en ambos / con diferencias.
3. Etapa 2b (opcional): indexador en la PC (.exe Flutter o script) que se corre a pedido y le pasa la lista a la app, para no leer todo por WiFi.

## 4. Decisiones tomadas
- 2026-11-23 App nueva (no módulo de Multi G-DRIVE ni de FotosCompare).
- 2026-11-24 Flutter — mismo ecosistema que Multi G-DRIVE/Reproductor; habilita indexador o versión Windows del mismo código.
- 2026-11-24 Etapa 1 sola en este paso, para no encarecer; Release Patch.
- 2026-11-24 Firma fija con los mismos Secrets de Notas/Multi G-DRIVE (desde v0.0.2; la v0.0.1 usó clave de prueba y hay que desinstalarla una vez).
- 2026-11-24 APK universal (3 arquitecturas, 46 MB): por ahora no se cambia.
- Sin borrado automático: cualquier acción futura se marca, se revisa y se confirma.

## 5. Pendientes / dudas abiertas
- [ ] Aviso de versión nueva y Changelog leyendo las Releases (como `updates.dart` de multigdrive), según ESTANDAR-VERSIONES.md.
- [ ] Guardar el último escaneo (hoy se pierde al cerrar la app); lo necesita la Etapa 2.
- [ ] Ícono propio de la app.
- [ ] Alta en Mi Panel y en la caja de apps (mapa-apps.md).

## 6. Datos técnicos clave
- Archivos principales: `lib/main.dart` (inicio, permisos, volúmenes), `lib/scanner.dart` (escaneo en isolate), `lib/results.dart` (pestañas), `lib/treemap.dart` (mapa), `lib/format.dart` (tamaños y tipos).
- Nativo: `tool/patch_platforms.py` escribe `MainActivity.kt` (canal `dc/storage`: `sdk`, `volumes`) y agrega los permisos al manifest. La carpeta `android/` no se versiona: la genera `flutter create` en Actions.
- Cómo se publica: push a main → GitHub Actions compila el APK (firmado con los Secrets ANDROID_KEYSTORE_BASE64 / _PASSWORD / ANDROID_KEY_ALIAS) → Release con el .apk adjunto.
- Releases: según `ESTANDAR-VERSIONES.md` del repo home (`[major]` / `[minor]` / `[patch]` / `[skip release]` en el commit; cambios que no tocan la app van sin release)

## 7. Historial (resumido)
- v0.0.2 2026-11-24 — Mapa: zoom, arrastre, detalle con presión larga, elementos chicos; barra de navegación ya no tapa la app.
- v0.0.1 2026-11-24 — Etapa 1: escaneo, Árbol, Mapa, Grandes y Tipos.

---
*Al cerrar cada sesión: actualizar secciones 1, 2, 3 y 7, y subir el archivo al repo.*
