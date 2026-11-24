import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

const _storage = MethodChannel('dc/storage');
const _smb = MethodChannel('dc/smb');

/// Carpeta de la app (privada) donde se guardan escaneos y ajustes.
Future<Directory> appDir() async {
  String? p;
  try {
    p = await _storage.invokeMethod<String>('filesDir');
  } catch (_) {}
  final d = Directory(p ?? '${Directory.systemTemp.path}/diskcompare');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

/// Exportar archivos (CSV): se escriben en la caché de la app y desde ahí
/// se copian a Descargas/DiskCompare o se comparten con el menú de Android.
class Exporter {
  static Future<Directory> dir() async {
    String? p;
    try {
      p = await _storage.invokeMethod<String>('cacheDir');
    } catch (_) {}
    final d = Directory('${p ?? Directory.systemTemp.path}/export');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Devuelve dónde quedó, por ejemplo "Descargas/DiskCompare/archivo.csv".
  static Future<String> saveToDownloads(String file, String name) async {
    try {
      return await _storage.invokeMethod<String>('saveDownload', {'path': file, 'name': name}) ?? name;
    } on PlatformException catch (e) {
      throw e.message ?? e.code;
    }
  }

  static Future<void> share(String file, String title) async {
    try {
      await _storage.invokeMethod('shareFile', {'path': file, 'title': title});
    } on PlatformException catch (e) {
      throw e.message ?? e.code;
    }
  }
}

/// Carpeta compartida de Windows: \\PC\Compartida\sub\carpeta
class PcTarget {
  final String host;
  final String share;
  final String path; // subcarpeta dentro de la compartida ('' = raíz), separada con '\'
  const PcTarget(this.host, this.share, this.path);

  static PcTarget? parse(String unc) {
    final parts = unc.trim().replaceAll('/', '\\').split('\\').where((p) => p.trim().isNotEmpty).toList();
    if (parts.length < 2) return null;
    return PcTarget(parts[0].trim(), parts[1].trim(), parts.skip(2).join('\\'));
  }

  String get unc => '\\\\$host\\$share${path.isEmpty ? '' : '\\$path'}';
}

/// Usuario y contraseña de Windows en la PC. "PC\usuario" separa el dominio.
class PcLogin {
  final String user;
  final String password;
  const PcLogin(this.user, this.password);

  Map<String, String> get args {
    final u = user.trim();
    final i = u.indexOf('\\');
    return {
      'user': i < 0 ? u : u.substring(i + 1),
      'domain': i < 0 ? '' : u.substring(0, i),
      'password': password,
    };
  }
}

class SmbError implements Exception {
  final String code;
  final String message;
  const SmbError(this.code, this.message);
  bool get cancelled => code == 'cancel';
  @override
  String toString() => message;
}

/// Resultado de leer la carpeta de la PC (lista guardada en un archivo .tsv).
class PcScan {
  final String file;
  final int files;
  final int bytes;
  final int denied; // carpetas que no se pudieron leer
  const PcScan(this.file, this.files, this.bytes, this.denied);
}

/// Acceso a la PC por SMB (la parte nativa está en SmbBridge.kt). Solo lectura.
class Smb {
  static void Function(int files, int bytes, String current)? onProgress;
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    _ready = true;
    _smb.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final m = call.arguments as Map;
        onProgress?.call((m['files'] as num).toInt(), (m['bytes'] as num).toInt(), m['current'] as String? ?? '');
      }
      return null;
    });
  }

  static Map<String, String> _args(PcTarget t, PcLogin l) =>
      {'host': t.host, 'share': t.share, 'path': t.path, ...l.args};

  /// Subcarpetas de una carpeta de la PC.
  static Future<List<String>> list(PcTarget t, PcLogin l) async {
    _init();
    try {
      return await _smb.invokeListMethod<String>('list', _args(t, l)) ?? <String>[];
    } on PlatformException catch (e) {
      throw SmbError(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw const SmbError('platform', 'La conexión con la PC solo funciona en Android.');
    }
  }

  /// Recorre toda la carpeta de la PC.
  static Future<PcScan> scan(PcTarget t, PcLogin l) async {
    _init();
    try {
      final m = await _smb.invokeMapMethod<String, Object?>('scan', _args(t, l)) ?? const {};
      return PcScan(m['path'] as String, (m['files'] as num).toInt(), (m['bytes'] as num).toInt(),
          (m['denied'] as num? ?? 0).toInt());
    } on PlatformException catch (e) {
      throw SmbError(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw const SmbError('platform', 'La conexión con la PC solo funciona en Android.');
    }
  }

  static Future<void> cancel() async {
    try {
      await _smb.invokeMethod('cancel');
    } catch (_) {}
  }
}

/// Textos guardados cifrados en el equipo (Android Keystore, ver Secret.kt).
class Secrets {
  static Future<void> save(String key, String value) =>
      _storage.invokeMethod('secretSave', {'key': key, 'value': value});

  static Future<String?> load(String key) async {
    try {
      return await _storage.invokeMethod<String>('secretLoad', {'key': key});
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.invokeMethod('secretDelete', {'key': key});
    } catch (_) {}
  }
}

/// Ajustes de la comparación (sin la contraseña, que va cifrada aparte).
class CompareConfig {
  String unc;
  String user;
  String phoneFolder;
  bool savePassword;
  bool byFolder; // comparar también por carpeta
  CompareConfig({this.unc = '', this.user = '', this.phoneFolder = '', this.savePassword = true, this.byFolder = false});

  static Future<File> _file() async => File('${(await appDir()).path}/compare.json');

  static Future<CompareConfig> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return CompareConfig();
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return CompareConfig(
        unc: m['unc'] as String? ?? '',
        user: m['user'] as String? ?? '',
        phoneFolder: m['phoneFolder'] as String? ?? '',
        savePassword: m['savePassword'] as bool? ?? true,
        byFolder: m['byFolder'] as bool? ?? false,
      );
    } catch (_) {
      return CompareConfig();
    }
  }

  Future<void> save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode(
        {'unc': unc, 'user': user, 'phoneFolder': phoneFolder, 'savePassword': savePassword, 'byFolder': byFolder}));
  }
}

/// Un archivo de un lado de la comparación. [path] es relativo a la carpeta comparada, con '/'.
class FEntry {
  final String path;
  final int size;
  final int mtime;
  const FEntry(this.path, this.size, this.mtime);

  String get name => path.substring(path.lastIndexOf('/') + 1);
  String get folder {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }
}

/// Lee el .tsv que escribió SmbBridge (en segundo plano). Devuelve archivos y carpetas sin permiso.
Future<(List<FEntry>, List<String>)> readPcScan(String file) => Isolate.run(() {
      final files = <FEntry>[];
      final denied = <String>[];
      for (final line in const LineSplitter().convert(File(file).readAsStringSync())) {
        if (line.isEmpty) continue;
        final p = line.split('\t');
        if (p[0] == '!') {
          denied.add(p.length > 1 ? p[1] : '');
        } else if (p.length >= 3) {
          files.add(FEntry(p[0], int.tryParse(p[1]) ?? 0, int.tryParse(p[2]) ?? 0));
        }
      }
      return (files, denied);
    });
