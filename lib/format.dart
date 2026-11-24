import 'package:flutter/material.dart';

/// 1536 → "1,5 KB" (base 1024, coma decimal).
String fmtSize(int b) {
  if (b < 1024) return '$b B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  double v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')} ${u[i]}';
}

/// 12345 → "12.345"
String fmtInt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// 0.256 → "26%" · 0.012 → "1,2%"
String fmtPct(double f) {
  final p = f * 100;
  final s = p >= 10 ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')}%';
}

String fmtDate(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Tipos de archivo (por extensión).
enum Kind {
  imagen('Imágenes', Icons.image_outlined, Color(0xFF7B1FA2)),
  video('Videos', Icons.movie_outlined, Color(0xFFC62828)),
  audio('Audio', Icons.music_note_outlined, Color(0xFF1565C0)),
  documento('Documentos', Icons.description_outlined, Color(0xFF2E7D32)),
  app('Apps (APK)', Icons.android, Color(0xFF558B2F)),
  comprimido('Comprimidos', Icons.folder_zip_outlined, Color(0xFFEF6C00)),
  otro('Otros', Icons.insert_drive_file_outlined, Color(0xFF546E7A));

  const Kind(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

const Map<String, Kind> _ext = {
  'jpg': Kind.imagen, 'jpeg': Kind.imagen, 'png': Kind.imagen, 'gif': Kind.imagen,
  'webp': Kind.imagen, 'heic': Kind.imagen, 'heif': Kind.imagen, 'bmp': Kind.imagen,
  'dng': Kind.imagen, 'raw': Kind.imagen, 'tif': Kind.imagen, 'tiff': Kind.imagen,
  'mp4': Kind.video, 'mkv': Kind.video, 'mov': Kind.video, 'avi': Kind.video,
  '3gp': Kind.video, 'webm': Kind.video, 'm4v': Kind.video, 'ts': Kind.video,
  'mp3': Kind.audio, 'm4a': Kind.audio, 'aac': Kind.audio, 'flac': Kind.audio,
  'wav': Kind.audio, 'ogg': Kind.audio, 'opus': Kind.audio, 'amr': Kind.audio,
  'pdf': Kind.documento, 'doc': Kind.documento, 'docx': Kind.documento,
  'xls': Kind.documento, 'xlsx': Kind.documento, 'ppt': Kind.documento,
  'pptx': Kind.documento, 'txt': Kind.documento, 'odt': Kind.documento,
  'csv': Kind.documento, 'epub': Kind.documento, 'md': Kind.documento,
  'apk': Kind.app, 'apks': Kind.app, 'xapk': Kind.app, 'obb': Kind.app,
  'zip': Kind.comprimido, 'rar': Kind.comprimido, '7z': Kind.comprimido,
  'tar': Kind.comprimido, 'gz': Kind.comprimido,
};

Kind kindOf(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0 || i == name.length - 1) return Kind.otro;
  return _ext[name.substring(i + 1).toLowerCase()] ?? Kind.otro;
}
