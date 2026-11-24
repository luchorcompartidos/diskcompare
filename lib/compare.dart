import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import 'format.dart';
import 'pc.dart';
import 'results.dart';
import 'scanner.dart';

const _passKey = 'pc-pass';

// ---------------------------------------------------------------------------
// Lógica: comparar por nombre + tamaño (sin importar en qué carpeta está)
// ---------------------------------------------------------------------------

/// El archivo está en los dos lados (mismo nombre y tamaño).
class BothRow {
  final FEntry phone;
  final FEntry pc;
  final int pcCopies; // cuántas copias iguales hay en la PC
  const BothRow(this.phone, this.pc, this.pcCopies);
}

/// El nombre está en los dos lados, pero con otro tamaño.
class DiffRow {
  final String name;
  final List<FEntry> phone; // copias del celular sin igual en la PC
  final List<FEntry> pc; // copias de la PC sin igual en el celular
  const DiffRow(this.name, this.phone, this.pc);

  int get size {
    var m = 0;
    for (final e in phone) {
      if (e.size > m) m = e.size;
    }
    for (final e in pc) {
      if (e.size > m) m = e.size;
    }
    return m;
  }
}

class CompareResult {
  final List<FEntry> onlyPhone;
  final List<FEntry> onlyPc;
  final List<BothRow> both;
  final List<DiffRow> diff;
  final int phoneFiles;
  final int pcFiles;
  const CompareResult(this.onlyPhone, this.onlyPc, this.both, this.diff, this.phoneFiles, this.pcFiles);
}

int _sum(Iterable<int> l) => l.fold(0, (a, b) => a + b);

CompareResult _compare(List<FEntry> phone, List<FEntry> pc) {
  Map<String, List<FEntry>> byName(List<FEntry> l) {
    final m = <String, List<FEntry>>{};
    for (final e in l) {
      (m[e.name.toLowerCase()] ??= <FEntry>[]).add(e); // Windows no distingue mayúsculas
    }
    return m;
  }

  final a = byName(phone);
  final b = byName(pc);
  final onlyPhone = <FEntry>[];
  final onlyPc = <FEntry>[];
  final both = <BothRow>[];
  final diff = <DiffRow>[];

  a.forEach((k, pl) {
    final ql = b[k];
    if (ql == null) {
      onlyPhone.addAll(pl);
      return;
    }
    final qBySize = <int, List<FEntry>>{};
    for (final q in ql) {
      (qBySize[q.size] ??= <FEntry>[]).add(q);
    }
    final pSizes = {for (final p in pl) p.size};
    final dp = <FEntry>[];
    for (final p in pl) {
      final m = qBySize[p.size];
      if (m != null) {
        both.add(BothRow(p, m.first, m.length));
      } else {
        dp.add(p);
      }
    }
    final dq = [for (final q in ql) if (!pSizes.contains(q.size)) q];
    if (dp.isNotEmpty || dq.isNotEmpty) diff.add(DiffRow(pl.first.name, dp, dq));
  });
  b.forEach((k, ql) {
    if (!a.containsKey(k)) onlyPc.addAll(ql);
  });

  onlyPhone.sort((x, y) => y.size.compareTo(x.size));
  onlyPc.sort((x, y) => y.size.compareTo(x.size));
  both.sort((x, y) => y.phone.size.compareTo(x.phone.size));
  diff.sort((x, y) => y.size.compareTo(x.size));
  return CompareResult(onlyPhone, onlyPc, both, diff, phone.length, pc.length);
}

/// Compara en segundo plano.
Future<CompareResult> compareFiles(List<FEntry> phone, List<FEntry> pc) => Isolate.run(() => _compare(phone, pc));

/// Archivos de un árbol escaneado, con la ruta relativa a su raíz.
List<FEntry> flattenNode(Node root) {
  final out = <FEntry>[];
  void walk(Node n, String prefix) {
    for (final c in n.children) {
      final p = prefix.isEmpty ? c.name : '$prefix/${c.name}';
      if (c.isDir) {
        walk(c, p);
      } else {
        out.add(FEntry(p, c.size, c.mtime));
      }
    }
  }

  walk(root, '');
  return out;
}

/// Arma un árbol (para ver la PC con Árbol, Mapa, Grandes y Tipos).
Node treeFromEntries(String label, List<FEntry> files, List<String> denied) {
  final root = Node(label, true);
  final dirs = <String, Node>{'': root};
  Node dirOf(String folder) {
    final d = dirs[folder];
    if (d != null) return d;
    final i = folder.lastIndexOf('/');
    final parent = dirOf(i < 0 ? '' : folder.substring(0, i));
    final n = Node(folder.substring(i + 1), true)..parent = parent;
    parent.children.add(n);
    dirs[folder] = n;
    return n;
  }

  for (final f in files) {
    final d = dirOf(f.folder);
    d.children.add(Node(f.name, false, size: f.size, files: 1, mtime: f.mtime)..parent = d);
  }
  for (final p in denied) {
    dirOf(p).restricted = true;
  }
  void total(Node n) {
    var s = 0, c = 0, m = 0;
    for (final k in n.children) {
      if (k.isDir) total(k);
      s += k.size;
      c += k.files;
      if (k.mtime > m) m = k.mtime;
    }
    n.size = s;
    n.files = c;
    n.mtime = m;
    n.children.sort((x, y) => y.size.compareTo(x.size));
  }

  total(root);
  return root;
}

Future<List<String>> listLocalDirs(String path) async {
  final out = <String>[];
  await for (final e in Directory(path).list(followLinks: false)) {
    if (e is Directory) out.add(e.path.substring(e.path.lastIndexOf('/') + 1));
  }
  out.sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase()));
  return out;
}

// ---------------------------------------------------------------------------
// Selector de carpetas (celular o PC)
// ---------------------------------------------------------------------------

class FolderPickerPage extends StatefulWidget {
  final String title;
  final String start;
  final Future<List<String>> Function(String path) list;
  final String Function(String path, String child) join;
  final String? Function(String path) parentOf;
  final String Function(String path) show;

  const FolderPickerPage({
    super.key,
    required this.title,
    required this.start,
    required this.list,
    required this.join,
    required this.parentOf,
    required this.show,
  });

  @override
  State<FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends State<FolderPickerPage> {
  late String _path = widget.start;
  List<String>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    final path = _path;
    try {
      final r = await widget.list(path);
      if (mounted && path == _path) setState(() => _items = r);
    } catch (e) {
      if (mounted && path == _path) setState(() => _error = '$e');
    }
  }

  void _go(String p) {
    _path = p;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final parent = widget.parentOf(_path);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: Text(widget.show(_path)),
          subtitle: const Text('Carpeta actual'),
        ),
        const Divider(height: 1),
        if (parent != null)
          ListTile(
            leading: const Icon(Icons.arrow_upward),
            title: const Text('Subir'),
            onTap: () => _go(parent),
          ),
        Expanded(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                )
              : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(child: Text('Sin subcarpetas'))
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) => ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(items[i]),
                            onTap: () => _go(widget.join(_path, items[i])),
                          ),
                        ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_path),
            icon: const Icon(Icons.check),
            label: const Text('Usar esta carpeta'),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pantalla "Comparar con la PC"
// ---------------------------------------------------------------------------

class ComparePage extends StatefulWidget {
  final List<(String, String)> volumes; // (ruta, nombre)
  final bool granted;
  const ComparePage({super.key, required this.volumes, required this.granted});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  final _unc = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  CompareConfig _cfg = CompareConfig();
  bool _loaded = false;
  bool _hasSavedPass = false;
  bool _showPass = false;
  String _phone = '';
  String? _phase; // 'phone' | 'pc' | 'compare'
  int _files = 0, _bytes = 0;
  String _current = '';
  String? _error;
  final _scanner = Scanner();

  @override
  void initState() {
    super.initState();
    _phone = widget.volumes.isEmpty ? '/storage/emulated/0' : widget.volumes.first.$1;
    _load();
  }

  @override
  void dispose() {
    _scanner.cancel();
    Smb.cancel();
    Smb.onProgress = null;
    _unc.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await CompareConfig.load();
    final pass = cfg.savePassword ? await Secrets.load(_passKey) : null;
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _unc.text = cfg.unc;
      _user.text = cfg.user;
      _pass.text = pass ?? '';
      _hasSavedPass = pass != null;
      if (cfg.phoneFolder.isNotEmpty && _volumeOf(cfg.phoneFolder) != null) {
        try {
          if (Directory(cfg.phoneFolder).existsSync()) _phone = cfg.phoneFolder;
        } catch (_) {}
      }
      _loaded = true;
    });
  }

  (String, String)? _volumeOf(String p) {
    for (final v in widget.volumes) {
      if (p == v.$1 || p.startsWith('${v.$1}/')) return v;
    }
    return null;
  }

  String _showLocal(String p) {
    final v = _volumeOf(p);
    if (v == null) return p;
    return v.$2 + p.substring(v.$1.length);
  }

  PcLogin get _login => PcLogin(_user.text, _pass.text);

  Future<void> _pickPhone() async {
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => FolderPickerPage(
        title: 'Carpeta del celular',
        start: _phone,
        list: listLocalDirs,
        join: (p, c) => '$p/$c',
        parentOf: (p) {
          if (widget.volumes.any((v) => v.$1 == p)) return null;
          final i = p.lastIndexOf('/');
          return i <= 0 ? null : p.substring(0, i);
        },
        show: _showLocal,
      ),
    ));
    if (r != null && mounted) setState(() => _phone = r);
  }

  Future<void> _pickPc() async {
    final t = PcTarget.parse(_unc.text);
    if (t == null) {
      setState(() => _error = r'Primero escribí la PC y la carpeta compartida, por ejemplo \\192.168.0.10\Fotos');
      return;
    }
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => FolderPickerPage(
        title: 'Carpeta de la PC',
        start: t.unc,
        list: (p) => Smb.list(PcTarget.parse(p)!, _login),
        join: (p, c) => '$p\\$c',
        parentOf: (p) {
          final x = PcTarget.parse(p)!;
          if (x.path.isEmpty) return null;
          final i = x.path.lastIndexOf('\\');
          return PcTarget(x.host, x.share, i < 0 ? '' : x.path.substring(0, i)).unc;
        },
        show: (p) => p,
      ),
    ));
    if (r != null && mounted) setState(() => _unc.text = r);
  }

  Future<void> _forgetPass() async {
    await Secrets.delete(_passKey);
    if (mounted) {
      setState(() {
        _hasSavedPass = false;
        _pass.clear();
      });
    }
  }

  void _progress(int f, int b, String c) {
    if (mounted) {
      setState(() {
        _files = f;
        _bytes = b;
        _current = c;
      });
    }
  }

  Future<void> _run() async {
    final t = PcTarget.parse(_unc.text);
    if (t == null) {
      setState(() => _error = r'Escribí la carpeta de la PC así: \\NOMBRE-PC\Compartida (o con la IP: \\192.168.0.10\Compartida).');
      return;
    }
    if (!widget.granted) {
      setState(() => _error = 'Falta el permiso de archivos: dalo desde la pantalla de inicio.');
      return;
    }
    FocusScope.of(context).unfocus();
    _cfg
      ..unc = t.unc
      ..user = _user.text.trim()
      ..phoneFolder = _phone;
    try {
      await _cfg.save();
    } catch (_) {}
    if (_cfg.savePassword && _pass.text.isNotEmpty) {
      try {
        await Secrets.save(_passKey, _pass.text);
        _hasSavedPass = true;
      } catch (_) {}
    } else if (!_cfg.savePassword) {
      await Secrets.delete(_passKey);
      _hasSavedPass = false;
    }
    setState(() {
      _error = null;
      _phase = 'phone';
      _files = 0;
      _bytes = 0;
      _current = '';
    });
    try {
      final root = await _scanner.scan(_phone, _progress);
      if (root == null || !mounted) {
        if (mounted) setState(() => _phase = null);
        return;
      }
      final phone = flattenNode(root);
      setState(() {
        _phase = 'pc';
        _files = 0;
        _bytes = 0;
        _current = '';
      });
      Smb.onProgress = _progress;
      final scan = await Smb.scan(t, _login);
      if (!mounted) return;
      setState(() => _phase = 'compare');
      final (pcFiles, denied) = await readPcScan(scan.file);
      final res = await compareFiles(phone, pcFiles);
      if (!mounted) return;
      setState(() => _phase = null);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CompareResultPage(
          result: res,
          phoneLabel: _showLocal(_phone),
          pcLabel: t.unc,
          phoneRoot: root,
          pcFiles: pcFiles,
          denied: denied,
        ),
      ));
    } on SmbError catch (e) {
      if (mounted) {
        setState(() {
          _phase = null;
          _error = e.cancelled ? null : e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = null;
          _error = 'No se pudo comparar: $e';
        });
      }
    } finally {
      Smb.onProgress = null;
    }
  }

  void _cancel() {
    if (_phase == 'phone') _scanner.cancel();
    if (_phase == 'pc') Smb.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase != null;
    final small = Theme.of(context).textTheme.bodySmall;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Comparar con la PC')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('1. Carpeta del celular', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (widget.volumes.length > 1)
                        Wrap(spacing: 8, children: [
                          for (final v in widget.volumes)
                            ChoiceChip(
                              label: Text(v.$2),
                              selected: _volumeOf(_phone)?.$1 == v.$1,
                              onSelected: busy ? null : (_) => setState(() => _phone = v.$1),
                            ),
                        ]),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.smartphone),
                        title: Text(_showLocal(_phone)),
                        trailing: TextButton(onPressed: busy ? null : _pickPhone, child: const Text('Elegir')),
                      ),
                    ]),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('2. Carpeta compartida de la PC', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _unc,
                        enabled: !busy,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Carpeta',
                          hintText: r'\\192.168.0.10\Fotos',
                          helperText: r'\\PC\Compartida\subcarpeta — si el nombre no anda, usá la IP de la PC',
                          prefixIcon: Icon(Icons.computer),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _user,
                        enabled: !busy,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Usuario de Windows',
                          helperText: r'El de esa PC (o la cuenta Microsoft). Vacío = invitado',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pass,
                        enabled: !busy,
                        obscureText: !_showPass,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showPass = !_showPass),
                          ),
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _cfg.savePassword,
                        onChanged: busy ? null : (v) => setState(() => _cfg.savePassword = v ?? true),
                        title: const Text('Guardar la contraseña en este equipo (cifrada)'),
                      ),
                      if (_hasSavedPass)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: busy ? null : _forgetPass,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Olvidar la contraseña guardada'),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : _pickPc,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Explorar carpetas de la PC'),
                        ),
                      ),
                    ]),
                  ),
                ),
                if (_error != null)
                  Card(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                    ),
                  ),
                const SizedBox(height: 8),
                if (busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(switch (_phase) {
                    'phone' => 'Leyendo el celular…',
                    'pc' => 'Leyendo la PC por WiFi…',
                    _ => 'Comparando…',
                  }),
                  if (_phase != 'compare') Text('${fmtInt(_files)} archivos · ${fmtSize(_bytes)}'),
                  if (_current.isNotEmpty)
                    Text(_current, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                  if (_phase != 'compare')
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: _cancel, child: const Text('Cancelar')),
                    ),
                ] else
                  FilledButton.icon(
                    onPressed: _run,
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Comparar'),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Se compara por nombre y tamaño, sin importar en qué subcarpeta esté cada archivo. '
                  'La app solo lee: no copia, mueve ni borra nada en el celular ni en la PC.',
                  style: small,
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resultado
// ---------------------------------------------------------------------------

class CompareResultPage extends StatefulWidget {
  final CompareResult result;
  final String phoneLabel;
  final String pcLabel;
  final Node phoneRoot;
  final List<FEntry> pcFiles;
  final List<String> denied;
  const CompareResultPage({
    super.key,
    required this.result,
    required this.phoneLabel,
    required this.pcLabel,
    required this.phoneRoot,
    required this.pcFiles,
    required this.denied,
  });

  @override
  State<CompareResultPage> createState() => _CompareResultPageState();
}

class _CompareResultPageState extends State<CompareResultPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  Node? _pcTree;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _pcPath(FEntry e) => '${widget.pcLabel}\\${e.path.replaceAll('/', '\\')}';
  String _phonePath(FEntry e) => '${widget.phoneLabel}/${e.path}';
  String _folder(FEntry e) => e.folder.isEmpty ? '(carpeta principal)' : e.folder;

  void _openTree(bool pc) {
    final Node root;
    if (pc) {
      root = _pcTree ??= treeFromEntries(widget.pcLabel, widget.pcFiles, widget.denied);
    } else {
      root = widget.phoneRoot;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsPage(root: root, label: pc ? 'PC' : widget.phoneLabel, used: 0),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparación'),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'Ver como árbol',
            icon: const Icon(Icons.account_tree_outlined),
            onSelected: _openTree,
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('Ver el celular (Árbol, Mapa…)')),
              PopupMenuItem(value: true, child: Text('Ver la PC (Árbol, Mapa…)')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Solo celular (${fmtInt(r.onlyPhone.length)})'),
            Tab(text: 'Solo PC (${fmtInt(r.onlyPc.length)})'),
            Tab(text: 'En ambos (${fmtInt(r.both.length)})'),
            Tab(text: 'Diferencias (${fmtInt(r.diff.length)})'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(controller: _tabs, children: [
          _list(
            'Están en el celular y en la PC no hay ningún archivo con ese nombre.',
            _sum(r.onlyPhone.map((e) => e.size)),
            r.onlyPhone.length,
            (i) => _entryTile(r.onlyPhone[i], phone: true),
          ),
          _list(
            'Están en la PC y en el celular no hay ningún archivo con ese nombre.'
            '${widget.denied.isEmpty ? '' : '\n${fmtInt(widget.denied.length)} carpetas de la PC no se pudieron leer (sin permiso).'}',
            _sum(r.onlyPc.map((e) => e.size)),
            r.onlyPc.length,
            (i) => _entryTile(r.onlyPc[i], phone: false),
          ),
          _list(
            'Mismo nombre y mismo tamaño en los dos lados (aunque estén en carpetas distintas).',
            _sum(r.both.map((e) => e.phone.size)),
            r.both.length,
            (i) => _bothTile(r.both[i]),
          ),
          _list(
            'Mismo nombre pero distinto tamaño: puede ser otra versión o una copia incompleta.',
            _sum(r.diff.map((e) => e.size)),
            r.diff.length,
            (i) => _diffTile(r.diff[i]),
          ),
        ]),
      ),
    );
  }

  Widget _list(String help, int bytes, int count, Widget Function(int i) row) {
    final r = widget.result;
    return ListView.builder(
      itemCount: count + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fmtInt(count)} archivos · ${fmtSize(bytes)}', style: Theme.of(context).textTheme.titleMedium),
              Text(help, style: Theme.of(context).textTheme.bodySmall),
              Text(
                'Celular: ${widget.phoneLabel} (${fmtInt(r.phoneFiles)}) · PC: ${widget.pcLabel} (${fmtInt(r.pcFiles)})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          );
        }
        return row(i - 1);
      },
    );
  }

  Widget _icon(String name) {
    final k = kindOf(name);
    return Icon(k.icon, color: k.color);
  }

  Widget _entryTile(FEntry e, {required bool phone}) => ListTile(
        dense: true,
        leading: _icon(e.name),
        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${fmtSize(e.size)} · ${_folder(e)}', maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _details(e.name, phone ? [e] : const [], phone ? const [] : [e]),
      );

  Widget _bothTile(BothRow b) => ListTile(
        dense: true,
        leading: _icon(b.phone.name),
        title: Text(b.phone.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${fmtSize(b.phone.size)} · Celular: ${_folder(b.phone)} · PC: ${_folder(b.pc)}'
          '${b.pcCopies > 1 ? ' (${b.pcCopies} copias)' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _details(b.phone.name, [b.phone], [b.pc]),
      );

  Widget _diffTile(DiffRow d) {
    String sizes(List<FEntry> l) => l.isEmpty ? '—' : l.map((e) => fmtSize(e.size)).join(', ');
    return ListTile(
      dense: true,
      leading: _icon(d.name),
      title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('Celular: ${sizes(d.phone)} · PC: ${sizes(d.pc)}', maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => _details(d.name, d.phone, d.pc),
    );
  }

  void _details(String name, List<FEntry> phone, List<FEntry> pc) {
    final small = Theme.of(context).textTheme.bodySmall;
    Widget side(String title, IconData icon, List<FEntry> l, String Function(FEntry) path) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Row(children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]),
            if (l.isEmpty) Text('—', style: small),
            for (final e in l) ...[
              const SizedBox(height: 4),
              SelectableText(path(e)),
              Text('${fmtSize(e.size)} (${fmtInt(e.size)} bytes) · ${fmtDate(e.mtime)}', style: small),
            ],
          ],
        );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            side('Celular', Icons.smartphone, phone, _phonePath),
            side('PC', Icons.computer, pc, _pcPath),
          ]),
        ),
      ),
    );
  }
}
