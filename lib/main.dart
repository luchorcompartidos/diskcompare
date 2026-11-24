import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'format.dart';
import 'results.dart';
import 'scanner.dart';

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
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
  final Map<String, Node> _last = {}; // último escaneo de cada volumen (en esta sesión)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
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
    }
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
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'DiskCompare',
              applicationVersion: 'v$appVersion',
              children: const [
                Text('Analizá qué ocupa lugar en tu celular: árbol de carpetas por tamaño, '
                    'mapa de bloques, archivos más grandes y totales por tipo.\n\n'
                    'Próxima etapa: comparar con una carpeta compartida de tu PC por WiFi.'),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
          children: [
            if (_granted == false) _permissionCard(),
            for (final v in _vols) _volumeCard(v),
            Card(
              child: ListTile(
                enabled: false,
                leading: const Icon(Icons.compare_arrows),
                title: const Text('Comparar con la PC (WiFi)'),
                subtitle: const Text('Próximamente: celular contra una carpeta compartida de Windows.'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('v$appVersion',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
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
