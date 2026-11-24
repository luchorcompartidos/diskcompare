import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'pc.dart';

/// Releases de GitHub: Changelog y aviso de versión nueva (estándar ESTANDAR-VERSIONES.md del repo home).
/// Sin paquetes extra (dart:io), para que siga compilando con Flutter 3.32 (APK android5-6).
const repoSlug = 'luchorcompartidos/diskcompare';
const repoUrl = 'https://github.com/$repoSlug';

const _ch = MethodChannel('dc/storage');

/// Abre un link en el navegador (o descarga el .apk).
Future<void> openUrl(String url) async {
  try {
    await _ch.invokeMethod('openUrl', {'url': url});
  } catch (_) {}
}

class ReleaseInfo {
  final String tag;
  final DateTime? date;
  final String notes; // solo la sección "Cambios"
  final String htmlUrl;
  final Map<String, String> assets; // nombre → link de descarga

  ReleaseInfo(this.tag, this.date, this.notes, this.htmlUrl, this.assets);

  String get version => tag.startsWith('v') ? tag.substring(1) : tag;

  /// El .apk de la misma arquitectura que la app instalada.
  String? apkFor(String abi) {
    final suffix = abi == 'armeabi-v7a' ? '-android5-6-armeabi-v7a.apk' : '-$abi.apk';
    for (final e in assets.entries) {
      if (abi.isNotEmpty && e.key.endsWith(suffix)) return e.value;
    }
    return null;
  }

  static String _changes(String body) {
    final b = body.replaceAll('\r', '').trim();
    final i = b.indexOf('## Cambios');
    final s = i < 0 ? b : b.substring(i + '## Cambios'.length);
    return s.trim();
  }

  factory ReleaseInfo.fromApi(Map<String, dynamic> j) {
    final assets = <String, String>{};
    DateTime? newest;
    for (final a in (j['assets'] as List? ?? const [])) {
      final m = a as Map<String, dynamic>;
      assets[m['name'] as String] = m['browser_download_url'] as String;
      final d = DateTime.tryParse('${m['updated_at']}');
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }
    return ReleaseInfo(
      j['tag_name'] as String,
      (newest ?? DateTime.tryParse('${j['published_at']}'))?.toLocal(),
      _changes((j['body'] as String?) ?? ''),
      j['html_url'] as String,
      assets,
    );
  }
}

class Updates {
  /// Releases (más nueva primero). Sin conexión: la última copia guardada.
  static Future<List<ReleaseInfo>> fetch() async {
    final cache = File('${(await appDir()).path}/releases.json');
    String? raw;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$repoSlug/releases?per_page=30'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'DiskCompare');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        raw = body;
        try {
          await cache.writeAsString(body);
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    if (raw == null) {
      try {
        if (cache.existsSync()) raw = await cache.readAsString();
      } catch (_) {}
    }
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((j) => ReleaseInfo.fromApi(j as Map<String, dynamic>))
          .where((r) => _parse(r.version) != null)
          .toList();
      list.sort((a, b) => compare(b.version, a.version));
      return list;
    } catch (_) {
      return [];
    }
  }

  static List<int>? _parse(String v) {
    final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(v);
    if (m == null) return null;
    return [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3] ?? '0')];
  }

  /// >0 si a es más nueva que b (ignora sufijos como "-prueba").
  static int compare(String a, String b) {
    final x = _parse(a) ?? [0, 0, 0], y = _parse(b) ?? [0, 0, 0];
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] - y[i];
    }
    return 0;
  }
}
