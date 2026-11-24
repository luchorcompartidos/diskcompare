# DiskCompare

App Android (Flutter) para ver qué ocupa lugar en el celular, al estilo **Disk Usage** + **TreeSize**,
y —en la próxima etapa— compararlo contra una carpeta compartida de una PC con Windows por WiFi.

## Qué hace (v0.0.2)
- **Árbol**: carpetas y archivos ordenados por tamaño, con barra y % del total. Tocá una carpeta para entrar.
- **Mapa**: bloques proporcionales al tamaño (squarified treemap). Tocá un bloque para entrar, mantené presionado para ver el detalle, pellizcá para hacer zoom y arrastrá. El bloque gris abre un mapa con los elementos chicos.
- **Grandes**: los 300 archivos más grandes, con filtro por tipo.
- **Tipos**: totales de imágenes, videos, audio, documentos, APK, comprimidos y otros.
- Almacenamiento interno y tarjeta SD, con espacio usado y libre.
- Solo lee: no modifica ni borra nada.

## Instalar
Descargá el `.apk` de la última [Release](https://github.com/luchorcompartidos/diskcompare/releases)
y abrilo en el celular. Al abrir la app, tocá **Dar acceso** y activá *Acceso a todos los archivos*.

## Límite de Android
Desde Android 11, las carpetas `Android/data` y `Android/obb` (datos internos de cada app) no se pueden
recorrer completas. La app muestra cuánto ocupa "lo que no se ve" (sistema y datos de apps).

## Cómo se compila
Cada push a `main` compila el APK en GitHub Actions (`.github/workflows/ci.yml`).
`[patch]`, `[minor]` o `[major]` en el mensaje del commit crea la Release.
