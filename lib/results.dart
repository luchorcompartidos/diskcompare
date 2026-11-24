import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';
import 'scanner.dart';
import 'treemap.dart';

/// Totales por tipo y lista de archivos ordenada por tamaño (se calcula una vez).
class _Stats {
  final List<(Node, Kind)> files;
  final Map<Kind, int> size;
  final Map<Kind, int> count;
  _Stats(this.files, this.size, this.count);

  factory _Stats.of(Node root) {
    final files = <(Node, Kind)>[];
    final size = <Kind, int>{};
    final count = <Kind, int>{};
    final stack = <Node>[root];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      for (final c in n.children) {
        if (c.isDir) {
          stack.add(c);
        } else {
          final k = kindOf(c.name);
          files.add((c, k));
          size[k] = (size[k] ?? 0) + c.size;
          count[k] = (count[k] ?? 0) + 1;
        }
      }
    }
    files.sort((a, b) => b.$1.size.compareTo(a.$1.size));
    return _Stats(files, size, count);
  }
}

class ResultsPage extends StatefulWidget {
  final Node root;
  final String label;
  final int used; // bytes usados del volumen (según Android)
  const ResultsPage({super.key, required this.root, required this.label, required this.used});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });
  late Node _cur = widget.root;
  final _tc = TransformationController(); // zoom del mapa
  final List<int> _rest = []; // mapa: "elementos chicos" abiertos (desde qué posición)
  Kind? _kind;
  _Stats? _statsCache;
  _Stats get _stats => _statsCache ??= _Stats.of(widget.root);

  static const _bigLimit = 300;

  @override
  void dispose() {
    _tabs.dispose();
    _tc.dispose();
    super.dispose();
  }

  bool get _inTree => _tabs.index <= 1;

  void _go(Node n) {
    _tc.value = Matrix4.identity();
    setState(() {
      _cur = n;
      _rest.clear();
    });
  }

  bool get _inRest => _tabs.index == 1 && _rest.isNotEmpty;

  void _up() {
    if (_inRest) {
      _tc.value = Matrix4.identity();
      setState(() => _rest.removeLast());
      return;
    }
    final p = _cur.parent;
    if (p != null) _go(p);
  }

  void _showInTree(Node file) {
    final p = file.parent;
    if (p != null) _go(p);
    _tabs.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_inTree || (_cur.isRoot && !_inRest),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.label),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.account_tree_outlined), text: 'Árbol'),
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Mapa'),
              Tab(icon: Icon(Icons.sort), text: 'Grandes'),
              Tab(icon: Icon(Icons.category_outlined), text: 'Tipos'),
            ],
          ),
        ),
        // SafeArea: que la barra de navegación de Android no tape la parte de abajo
        body: SafeArea(
          top: false,
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: [_treeTab(), _mapTab(), _bigTab(), _typesTab()],
          ),
        ),
      ),
    );
  }

  // ---------- Encabezado común de Árbol y Mapa ----------

  Widget _crumbs() {
    final chain = <Node>[];
    for (Node? n = _cur; n != null; n = n.parent) {
      chain.insert(0, n);
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: chain.length,
        separatorBuilder: (_, __) => const Icon(Icons.chevron_right, size: 18),
        itemBuilder: (_, i) {
          final n = chain[i];
          final last = i == chain.length - 1;
          return Center(
            child: InkWell(
              onTap: last ? null : () => _go(n),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  i == 0 ? widget.label : n.name,
                  style: TextStyle(
                    fontWeight: last ? FontWeight.bold : FontWeight.normal,
                    color: last ? null : scheme.primary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summary() {
    final small = Theme.of(context).textTheme.bodySmall;
    final lines = <Widget>[
      Text('${fmtSize(_cur.size)} · ${fmtInt(_cur.files)} archivos',
          style: Theme.of(context).textTheme.titleMedium),
    ];
    if (_cur.isRoot && widget.used > 0) {
      final hidden = math.max(0, widget.used - _cur.size);
      lines.add(Text(
          'De ${fmtSize(widget.used)} usados: ${fmtSize(_cur.size)} visibles y '
          '${fmtSize(hidden)} de sistema y datos internos de apps (Android no deja verlos).',
          style: small));
    }
    if (_cur.restricted) {
      lines.add(Text('Android limita lo que se puede ver en esta carpeta: el tamaño real puede ser mayor.',
          style: small?.copyWith(color: Theme.of(context).colorScheme.error)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
  }

  // ---------- Árbol (estilo TreeSize) ----------

  Widget _treeTab() {
    final kids = _cur.children;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _crumbs(),
        _summary(),
        const Divider(height: 1),
        Expanded(
          child: kids.isEmpty
              ? Center(child: Text(_cur.restricted ? 'Sin acceso al contenido' : 'Carpeta vacía'))
              : ListView.builder(
                  itemCount: kids.length,
                  itemBuilder: (_, i) => _row(kids[i], _cur.size),
                ),
        ),
      ],
    );
  }

  Widget _row(Node n, int parentSize, {String? subtitle, VoidCallback? onTap}) {
    final f = parentSize > 0 ? (n.size / parentSize).clamp(0.0, 1.0) : 0.0;
    final kind = n.isDir ? null : kindOf(n.name);
    final small = Theme.of(context).textTheme.bodySmall;
    final sub = subtitle ??
        (n.isDir
            ? '${fmtInt(n.files)} archivos${n.restricted ? ' · acceso limitado' : ''}'
            : fmtDate(n.mtime));
    return InkWell(
      onTap: onTap ?? (n.isDir ? () => _go(n) : () => _details(n)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              n.isDir ? (n.restricted ? Icons.folder_off_outlined : Icons.folder) : kind!.icon,
              color: n.isDir ? Colors.amber.shade700 : kind!.color,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(n.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall)),
                    const SizedBox(width: 8),
                    Text(fmtSize(n.size), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: f, minHeight: 6),
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Expanded(
                        child: Text(sub, style: small, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(fmtPct(f), style: small),
                  ]),
                ],
              ),
            ),
            if (n.isDir) const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  void _details(Node n) {
    final kind = n.isDir ? null : kindOf(n.name);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(n.isDir ? Icons.folder : kind!.icon,
                    color: n.isDir ? Colors.amber.shade700 : kind!.color),
                const SizedBox(width: 8),
                Expanded(child: Text(n.name, style: Theme.of(ctx).textTheme.titleMedium)),
              ]),
              const SizedBox(height: 12),
              Text('Tamaño: ${fmtSize(n.size)} (${fmtInt(n.size)} bytes)'),
              if (n.isDir) Text('Contiene: ${fmtInt(n.files)} archivos') else Text('Tipo: ${kind!.label}'),
              if (n.mtime > 0) Text('${n.isDir ? 'Último cambio adentro' : 'Modificado'}: ${fmtDate(n.mtime)}'),
              if (n.restricted) const Text('Android limita lo que se puede ver en esta carpeta.'),
              const SizedBox(height: 8),
              SelectableText('${n.isDir ? 'Ruta' : 'Carpeta'}: ${n.isDir ? n.path : n.parent?.path ?? ''}',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (n.isDir)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _go(n);
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Entrar'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (n.isDir) {
                      _go(n);
                      _tabs.animateTo(0);
                    } else {
                      _showInTree(n);
                    }
                  },
                  icon: const Icon(Icons.account_tree_outlined),
                  label: Text(n.isDir ? 'Ver en el Árbol' : 'Ver su carpeta en el Árbol'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Mapa (estilo Disk Usage) ----------

  Widget _mapTab() {
    final start = _rest.isEmpty ? 0 : _rest.last;
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _crumbs(),
        if (start == 0)
          _summary()
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Elementos chicos de "${_cur.isRoot ? widget.label : _cur.name}": '
              '${fmtInt(_cur.children.length - start)} elementos · '
              '${fmtSize(_cur.children.skip(start).fold<int>(0, (a, n) => a + n.size))}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: LayoutBuilder(builder: (_, c) {
              final items = layoutTreemap(_cur, Offset.zero & c.biggest, start: start);
              if (items.isEmpty) {
                return Center(child: Text(_cur.restricted ? 'Sin acceso al contenido' : 'Carpeta vacía'));
              }
              return ClipRect(
                child: Stack(children: [
                  InteractiveViewer(
                    transformationController: _tc,
                    minScale: 1,
                    maxScale: 40,
                    child: GestureDetector(
                      onTapUp: (d) => _tapBlock(hitTreemap(items, d.localPosition)),
                      onLongPressStart: (d) {
                        final it = hitTreemap(items, d.localPosition);
                        if (it != null && !it.node.synthetic) _details(it.node);
                      },
                      child: ListenableBuilder(
                        listenable: _tc,
                        builder: (_, __) => CustomPaint(
                          size: c.biggest,
                          painter: TreemapPainter(items, _tc.value.getMaxScaleOnAxis()),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: ListenableBuilder(
                      listenable: _tc,
                      builder: (_, __) => _tc.value.getMaxScaleOnAxis() > 1.01
                          ? IconButton.filledTonal(
                              tooltip: 'Ver todo',
                              icon: const Icon(Icons.zoom_out_map),
                              onPressed: () => _tc.value = Matrix4.identity(),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Tocá para entrar · Mantené presionado para ver el detalle · '
            'Pellizcá para hacer zoom${(_cur.isRoot && start == 0) ? '' : ' · Atrás para volver'}',
            style: small,
          ),
        ),
      ],
    );
  }

  void _tapBlock(TmItem? it) {
    if (it == null) return;
    final n = it.node;
    if (it.restStart != null) {
      // Bloque gris: abre un mapa solo con los elementos chicos
      _tc.value = Matrix4.identity();
      setState(() => _rest.add(it.restStart!));
    } else if (n.isDir) {
      _go(n);
    } else {
      _details(n);
    }
  }

  // ---------- Archivos más grandes ----------

  Widget _bigTab() {
    final all = _stats.files;
    final list = (_kind == null ? all : all.where((e) => e.$2 == _kind)).take(_bigLimit).toList();
    final top = list.isEmpty ? 0 : list.first.$1.size;
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('Todos'),
                  selected: _kind == null,
                  onSelected: (_) => setState(() => _kind = null),
                ),
              ),
              for (final k in Kind.values)
                if ((_stats.count[k] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      avatar: Icon(k.icon, size: 18, color: k.color),
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = _kind == k ? null : k),
                    ),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Los ${list.length} más grandes${_kind == null ? '' : ' de ${_kind!.label}'}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No hay archivos'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final n = list[i].$1;
                    return _row(n, top,
                        subtitle: n.parent?.path.replaceFirst(widget.root.name, '') ?? '',
                        onTap: () => _details(n));
                  },
                ),
        ),
      ],
    );
  }

  // ---------- Por tipo ----------

  Widget _typesTab() {
    final s = _stats;
    final total = widget.root.size;
    final kinds = Kind.values.where((k) => (s.count[k] ?? 0) > 0).toList()
      ..sort((a, b) => (s.size[b] ?? 0).compareTo(s.size[a] ?? 0));
    final small = Theme.of(context).textTheme.bodySmall;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final k in kinds)
          InkWell(
            onTap: () {
              setState(() => _kind = k);
              _tabs.animateTo(2);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                CircleAvatar(
                    backgroundColor: k.color.withValues(alpha: 0.15),
                    child: Icon(k.icon, color: k.color)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(k.label, style: Theme.of(context).textTheme.titleSmall)),
                      Text(fmtSize(s.size[k] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total > 0 ? ((s.size[k] ?? 0) / total).clamp(0.0, 1.0) : 0,
                        minHeight: 6,
                        color: k.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(children: [
                      Expanded(child: Text('${fmtInt(s.count[k] ?? 0)} archivos', style: small)),
                      Text(fmtPct(total > 0 ? (s.size[k] ?? 0) / total : 0), style: small),
                    ]),
                  ]),
                ),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
      ],
    );
  }
}
