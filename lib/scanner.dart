import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Un archivo o carpeta del árbol escaneado.
class Node {
  final String name;
  final bool isDir;
  int size; // bytes (para carpetas: la suma de todo lo de adentro)
  int files; // cantidad de archivos (para un archivo: 1)
  int mtime; // última modificación, en ms
  bool restricted; // Android no deja ver todo su contenido
  final bool synthetic; // agrupador "N elementos más" del mapa
  final List<Node> children = [];
  Node? parent;

  Node(this.name, this.isDir,
      {this.size = 0, this.files = 0, this.mtime = 0, this.restricted = false, this.synthetic = false});

  String get path => parent == null ? name : '${parent!.path}/$name';
  bool get isRoot => parent == null;
}

/// Carpetas que Android 11+ no deja recorrer completas (datos privados de cada app).
bool _isRestrictedPath(String p) => p.endsWith('/Android/data') || p.endsWith('/Android/obb');

/// Corre en un isolate aparte para no trabar la pantalla.
void _scanEntry(List<Object> args) {
  final port = args[0] as SendPort;
  final rootPath = args[1] as String;
  final root = Node(rootPath, true);
  var files = 0, bytes = 0, tick = 0;

  void walk(Directory dir, Node node) {
    if (_isRestrictedPath(dir.path)) node.restricted = true;
    List<FileSystemEntity> list;
    try {
      list = dir.listSync(followLinks: false);
    } catch (_) {
      node.restricted = true;
      return;
    }
    for (final e in list) {
      final name = e.path.substring(e.path.lastIndexOf('/') + 1);
      if (e is Directory) {
        final child = Node(name, true);
        walk(e, child);
        node.children.add(child);
        node.size += child.size;
        node.files += child.files;
        if (child.mtime > node.mtime) node.mtime = child.mtime;
      } else if (e is File) {
        var size = 0, mt = 0;
        try {
          final st = e.statSync();
          size = st.size;
          mt = st.modified.millisecondsSinceEpoch;
        } catch (_) {}
        node.children.add(Node(name, false, size: size, files: 1, mtime: mt));
        node.size += size;
        node.files += 1;
        if (mt > node.mtime) node.mtime = mt;
        files++;
        bytes += size;
        if (++tick >= 400) {
          tick = 0;
          port.send(['p', files, bytes, dir.path]);
        }
      }
    }
    node.children.sort((a, b) => b.size.compareTo(a.size));
  }

  walk(Directory(rootPath), root);
  Isolate.exit(port, root);
}

/// Escanea una carpeta completa en segundo plano.
class Scanner {
  Isolate? _iso;
  ReceivePort? _rp;
  Completer<Node?>? _done;

  bool get running => _done != null && !_done!.isCompleted;

  Future<Node?> scan(String root, void Function(int files, int bytes, String current) onProgress) async {
    final rp = ReceivePort();
    final done = Completer<Node?>();
    _rp = rp;
    _done = done;
    rp.listen((m) {
      if (m is List && m.isNotEmpty && m[0] == 'p') {
        onProgress(m[1] as int, m[2] as int, m[3] as String);
      } else if (m is Node) {
        _link(m);
        _finish(m);
      } else if (m is List) {
        // Error del isolate: [mensaje, pila]
        _fail('${m.isEmpty ? 'Error desconocido' : m.first}');
      }
    });
    _iso = await Isolate.spawn(_scanEntry, <Object>[rp.sendPort, root], onError: rp.sendPort);
    return done.future;
  }

  /// Corta el escaneo en curso (devuelve null).
  void cancel() {
    _iso?.kill(priority: Isolate.immediate);
    _finish(null);
  }

  void _finish(Node? n) {
    _rp?.close();
    _iso = null;
    final d = _done;
    if (d != null && !d.isCompleted) d.complete(n);
  }

  void _fail(String msg) {
    _rp?.close();
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    final d = _done;
    if (d != null && !d.isCompleted) d.completeError(Exception(msg));
  }

  static void _link(Node root) {
    final stack = <Node>[root];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      for (final c in n.children) {
        c.parent = n;
        if (c.isDir) stack.add(c);
      }
    }
  }
}
