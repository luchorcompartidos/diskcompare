# DiskCompare

App Android (Flutter) para ver qué ocupa lugar en el celular, al estilo **Disk Usage** + **TreeSize**,
y —en la próxima etapa— compararlo contra una carpeta compartida de una PC con Windows por WiFi.

## Qué hace (v0.0.3)
- **Árbol**: carpetas y archivos ordenados por tamaño, con barra y % del total. Tocá una carpeta para entrar.
- **Mapa**: bloques proporcionales al tamaño (squarified treemap). Tocá un bloque para entrar, mantené presionado para ver el detalle, pellizcá para hacer zoom y arrastrá. El bloque gris abre un mapa con los elementos chicos.
- **Grandes**: los 300 archivos más grandes, con filtro por tipo.
- **Tipos**: totales de imágenes, videos, audio, documentos, APK, comprimidos y otros.
- Almacenamiento interno y tarjeta SD, con espacio usado y libre.
- Solo lee: no modifica ni borra nada.

## Instalar
Descargá de la última [Release](https://github.com/luchorcompartidos/diskcompare/releases) el `.apk` que corresponda y abrilo:

| Archivo | Arquitectura | Para |
|---|---|---|
| `diskcompare-vX.Y.Z-arm64-v8a.apk` | arm64-v8a | Celulares y tablets con Android 7 o más (64 bits) |
| `diskcompare-vX.Y.Z-android5-6-armeabi-v7a.apk` | armeabi-v7a | Equipos con Android 5 o 6 (y Android de 32 bits) |
 Al abrir la app, tocá **Dar acceso** y activá *Acceso a todos los archivos*.

## Límite de Android
Desde Android 11, las carpetas `Android/data` y `Android/obb` (datos internos de cada app) no se pueden
recorrer completas. La app muestra cuánto ocupa "lo que no se ve" (sistema y datos de apps).

## Cómo se compila
Cada push a `main` compila el APK en GitHub Actions (`.github/workflows/ci.yml`).
`[patch]`, `[minor]` o `[major]` en el mensaje del commit crea la Release.
