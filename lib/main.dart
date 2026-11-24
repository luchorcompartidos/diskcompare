import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'compare.dart';
import 'format.dart';
import 'results.dart';
import 'scanner.dart';
import 'store.dart';
import 'updates.dart';

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
const appAbi = String.fromEnvironment('APP_ABI', defaultValue: '');
const appVersionText = appAbi == '' ? 'v$appVersion' : 'v$appVersion · $appAbi';
const _seed = Color(0xFF00897B);

void main() => runApp(const DiskCompareApp());

class DiskCompareApp extends StatelessWidget {
  const DiskCompareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiskCompare',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

/// Un almacenamiento del celular (interno o tarjeta SD).
class Volume {
  final String path;
  final String label;
  final int total;
  final int free;
  final bool removable;
  const Volume(this.path, this.label, this.total, this.free, this.removable);

  int get used => total - free;

  factory Volume.fromMap(Map m) => Volume(
        m['path'] as String,
        m['label'] as String? ?? 'Almacenamiento',
        (m['total'] as num?)?.toInt() ?? 0,
        (m['free'] as num?)?.toInt() ?? 0,
        m['removable'] as bool? ?? false,
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _ch = MethodChannel('dc/storage');

  bool? _granted;
  int _sdk = 30;
  List<Volume> _vols = [];
  final _scanner = Scanner();
  String? _scanning; // ruta del volumen que se está escaneando
  int _files = 0, _bytes = 0;
  String _current = '';
  final Map<String, Node> _last = {}; // último escaneo de cada volumen (queda guardado)
  final Map<String, int> _lastAt = {}; // cuándo se hizo
  bool _savedLoaded = false;
  List<ReleaseInfo> _releases = [];

  ReleaseInfo? get _newer {
    if (_releases.isEmpty || appVersion == 'dev') return null;
    final latest = _releases.first;
    return Updates.compare(latest.version, appVersion) > 0 ? latest : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    Updates.fetch().then((r) {
      if (mounted) setState(() => _releases = r);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de la pantalla de permisos de Android
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    var sdk = _sdk;
    var vols = _vols;
    try {
      sdk = await _ch.invokeMethod<int>('sdk') ?? sdk;
      final r = await _ch.invokeListMethod<Map>('volumes');
      vols = [for (final m in r ?? const <Map>[]) Volume.fromMap(m)];
    } catch (_) {}
    if (vols.isEmpty) {
      vols = const [Volume('/storage/emulated/0', 'Almacenamiento interno', 0, 0, false)];
    }
    final g = await _hasPermission(sdk);
    if (mounted) {
      setState(() {
        _sdk = sdk;
        _vols = vols;
        _granted = g;
      });
      _loadSaved();
    }
  }

  /// Trae los escaneos guardados (una sola vez, al abrir la app).
  Future<void> _loadSaved() async {
    if (_savedLoaded) return;
    _savedLoaded = true;
    for (final v in _vols) {
      final s = await loadScan(v.path);
      if (s != null && mounted && !_last.containsKey(v.path)) {
        setState(() {
          _last[v.path] = s.root;
          _lastAt[v.path] = s.at;
        });
      }
    }
  }

  Future<void> _save(Volume v, Node root) async {
    try {
      final at = await saveScan(v.path, root);
      if (mounted) setState(() => _lastAt[v.path] = at);
    } catch (_) {}
  }

  Future<bool> _hasPermission(int sdk) async {
    if (!Platform.isAndroid) return true;
    if (sdk >= 30) return Permission.manageExternalStorage.isGranted;
    return Permission.storage.isGranted;
  }

  Future<void> _askPermission() async {
    if (_sdk >= 30) {
      await Permission.manageExternalStorage.request();
    } else {
      await Permission.storage.request();
    }
    await _refresh();
  }

  Future<void> _scan(Volume v) async {
    setState(() {
      _scanning = v.path;
      _files = 0;
      _bytes = 0;
      _current = v.path;
    });
    try {
      final root = await _scanner.scan(v.path, (f, b, c) {
        if (mounted) {
          setState(() {
            _files = f;
            _bytes = b;
            _current = c;
          });
        }
      });
      if (root != null && mounted) {
        _last[v.path] = root;
        _lastAt[v.path] = DateTime.now().millisecondsSinceEpoch;
        _save(v, root);
        setState(() => _scanning = null);
        _open(v, root);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo analizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _scanning = null);
    }
  }

  void _open(Volume v, Node root) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsPage(root: root, label: v.label, used: v.used),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DiskCompare'),
        actions: [
          IconButton(
            tooltip: 'Acerca de',
            icon: const Icon(Icons.info_outline),
            onPressed: _showVersion,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
          children: [
            if (_newer != null) _updateCard(_newer!),
            if (_granted == false) _permissionCard(),
            for (final v in _vols) _volumeCard(v),
            Card(
              child: ListTile(
                enabled: _scanning == null,
                leading: const Icon(Icons.compare_arrows),
                title: const Text('Comparar con la PC (WiFi)'),
                subtitle: const Text('Una carpeta del celular contra una carpeta compartida de Windows.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ComparePage(
                    volumes: [for (final v in _vols) (v.path, v.label)],
                    granted: _granted == true,
                  ),
                )),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _showVersion,
                child: Text('$appVersionText · Changelog', style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openUpdate(ReleaseInfo r) => openUrl(r.apkFor(appAbi) ?? r.htmlUrl);

  Widget _updateCard(ReleaseInfo r) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.system_update),
        title: Text('Hay una versión nueva (v${r.version})'),
        subtitle: Text(r.apkFor(appAbi) != null ? 'Se descarga el APK $appAbi' : 'Abre la Release en GitHub'),
        trailing: FilledButton(onPressed: () => _openUpdate(r), child: const Text('Descargar')),
        onTap: _showVersion,
      ),
    );
  }

  void _showVersion() {
    final matches = _releases.where((r) => r.version == appVersion);
    final ReleaseInfo? current = matches.isEmpty ? null : matches.first;
    final newer = _newer;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('DiskCompare $appVersionText'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            if (current != null && current.date != null)
              Text('Publicada: ${fmtDate(current.date!.millisecondsSinceEpoch)}'),
            if (newer != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Hay una versión nueva: v${newer.version}',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 12),
            const Text('Analizá qué ocupa lugar en tu celular (árbol, mapa, archivos grandes y tipos) '
                'y compará una carpeta con una carpeta compartida de tu PC por WiFi. '
                'Solo lee: no modifica ni borra nada.'),
            const SizedBox(height: 16),
            Text('Changelog', style: Theme.of(ctx).textTheme.titleMedium),
            if (_releases.isEmpty) const Text('Sin conexión y sin copia guardada.'),
            for (final r in _releases.take(15)) ...[
              const SizedBox(height: 10),
              Text('v${r.version}${r.date == null ? '' : ' · ${fmtDate(r.date!.millisecondsSinceEpoch)}'}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (r.notes.isNotEmpty) Text(r.notes),
            ],
          ]),
        ),
        actions: [
          if (newer != null)
            FilledButton(onPressed: () => _openUpdate(newer), child: const Text('Descargar')),
          TextButton(onPressed: () => openUrl('$repoUrl/releases'), child: const Text('Ver en GitHub')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _permissionCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Falta el permiso de archivos',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: 6),
            Text(
              'Para medir todas las carpetas, Android pide activar "Acceso a todos los archivos" '
              'para DiskCompare. La app solo lee nombres y tamaños: no modifica ni borra nada.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _askPermission,
              icon: const Icon(Icons.lock_open),
              label: const Text('Dar acceso'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _volumeCard(Volume v) {
    final scanningThis = _scanning == v.path;
    final busy = _scanning != null;
    final last = _last[v.path];
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(v.removable ? Icons.sd_card_outlined : Icons.smartphone, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.label, style: Theme.of(context).textTheme.titleMedium),
                  Text(v.path, style: small),
                ]),
              ),
            ]),
            if (v.total > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: (v.used / v.total).clamp(0.0, 1.0), minHeight: 10),
              ),
              const SizedBox(height: 4),
              Text('${fmtSize(v.used)} usados de ${fmtSize(v.total)} · ${fmtSize(v.free)} libres',
                  style: small),
            ],
            if (last != null && _lastAt[v.path] != null) ...[
              const SizedBox(height: 4),
              Text('Último análisis: ${fmtDate(_lastAt[v.path]!)} · ${fmtSize(last.size)}', style: small),
            ],
            const SizedBox(height: 12),
            if (scanningThis) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('${fmtInt(_files)} archivos · ${fmtSize(_bytes)}'),
              Text(_current == v.path ? '/' : _current.replaceFirst(v.path, ''),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _scanner.cancel, child: const Text('Cancelar')),
              ),
            ] else
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: (_granted == true && !busy) ? () => _scan(v) : null,
                  icon: const Icon(Icons.search),
                  label: Text(last == null ? 'Analizar' : 'Volver a analizar'),
                ),
                if (last != null)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _open(v, last),
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('Ver resultado'),
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}
