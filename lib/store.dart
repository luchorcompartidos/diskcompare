import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'pc.dart';
import 'scanner.dart';

/// Último escaneo guardado de un volumen (sobrevive al cerrar la app).
class SavedScan {
  final Node root;
  final int at; // cuándo se hizo, en ms
  const SavedScan(this.root, this.at);
}

String _fileName(String volPath) =>
    'scan-${base64Url.encode(utf8.encode(volPath)).replaceAll('=', '')}.json.gz';

// Formato compacto: archivo = [nombre, tamaño, fecha]; carpeta = [nombre, tamaño, archivos, fecha, restringida, [hijos]]
List<Object> _enc(Node n) => n.isDir
    ? [n.name, n.size, n.files, n.mtime, n.restricted ? 1 : 0, [for (final c in n.children) _enc(c)]]
    : [n.name, n.size, n.mtime];

Node _dec(List<dynamic> l) {
  if (l.length == 3) {
    return Node(l[0] as String, false, size: l[1] as int, files: 1, mtime: l[2] as int);
  }
  final n = Node(l[0] as String, true,
      size: l[1] as int, files: l[2] as int, mtime: l[3] as int, restricted: l[4] == 1);
  for (final c in l[5] as List<dynamic>) {
    n.children.add(_dec(c as List<dynamic>));
  }
  return n;
}

/// Guarda el escaneo en la carpeta privada de la app (comprimido, en segundo plano).
Future<int> saveScan(String volPath, Node root) async {
  final dir = (await appDir()).path;
  final at = DateTime.now().millisecondsSinceEpoch;
  final name = _fileName(volPath);
  final data = _enc(root);
  await Isolate.run(() {
    final bytes = gzip.encode(utf8.encode(jsonEncode({'v': 1, 'path': volPath, 'at': at, 'root': data})));
    final tmp = File('$dir/$name.tmp')..writeAsBytesSync(bytes, flush: true);
    tmp.renameSync('$dir/$name');
  });
  return at;
}

/// Lee el último escaneo guardado de un volumen (null si no hay o si está dañado).
Future<SavedScan?> loadScan(String volPath) async {
  final f = File('${(await appDir()).path}/${_fileName(volPath)}');
  if (!f.existsSync()) return null;
  try {
    final s = await Isolate.run(() {
      final m = jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync()))) as Map<String, dynamic>;
      return SavedScan(_dec(m['root'] as List<dynamic>), m['at'] as int);
    });
    linkTree(s.root);
    return s;
  } catch (_) {
    return null;
  }
}
