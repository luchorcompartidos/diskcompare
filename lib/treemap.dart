import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';
import 'scanner.dart';

class TmItem {
  final Node node;
  final double value;
  Rect rect = Rect.zero;
  TmItem(this.node, this.value);
}

/// Mapa de bloques "squarified": cada bloque ocupa un área proporcional a su tamaño.
List<TmItem> layoutTreemap(Node parent, Rect area, {int maxItems = 150}) {
  final kids = parent.children.where((n) => n.size > 0).toList();
  if (kids.isEmpty || area.width <= 0 || area.height <= 0) return [];
  var shown = kids;
  if (kids.length > maxItems) {
    final rest = kids.sublist(maxItems - 1);
    final other = Node('${rest.length} elementos más', false,
        size: rest.fold<int>(0, (s, n) => s + n.size), synthetic: true)
      ..parent = parent;
    shown = [...kids.sublist(0, maxItems - 1), other];
  }
  final total = shown.fold<int>(0, (s, n) => s + n.size).toDouble();
  final scale = area.width * area.height / total;
  final items = [for (final n in shown) TmItem(n, n.size * scale)]
    ..sort((a, b) => b.value.compareTo(a.value));
  _squarify(items, area);
  return items;
}

void _squarify(List<TmItem> items, Rect area) {
  var rect = area;
  var row = <TmItem>[];
  var i = 0;
  while (i < items.length) {
    final side = math.min(rect.width, rect.height);
    final next = [...row, items[i]];
    if (row.isEmpty || _worst(next, side) <= _worst(row, side)) {
      row = next;
      i++;
    } else {
      rect = _layoutRow(row, rect);
      row = [];
    }
  }
  if (row.isNotEmpty) _layoutRow(row, rect);
}

double _worst(List<TmItem> row, double side) {
  var s = 0.0, mx = 0.0, mn = double.infinity;
  for (final it in row) {
    s += it.value;
    mx = math.max(mx, it.value);
    mn = math.min(mn, it.value);
  }
  if (s <= 0 || mn <= 0 || side <= 0) return double.infinity;
  final w2 = side * side, s2 = s * s;
  return math.max(w2 * mx / s2, s2 / (w2 * mn));
}

Rect _layoutRow(List<TmItem> row, Rect rect) {
  final s = row.fold<double>(0, (a, it) => a + it.value);
  if (rect.width >= rect.height) {
    // Columna a la izquierda
    final w = rect.height > 0 ? s / rect.height : 0.0;
    var y = rect.top;
    for (final it in row) {
      final h = w > 0 ? it.value / w : 0.0;
      it.rect = Rect.fromLTWH(rect.left, y, w, h);
      y += h;
    }
    return Rect.fromLTWH(rect.left + w, rect.top, math.max(0, rect.width - w), rect.height);
  } else {
    // Fila arriba
    final h = rect.width > 0 ? s / rect.width : 0.0;
    var x = rect.left;
    for (final it in row) {
      final w = h > 0 ? it.value / h : 0.0;
      it.rect = Rect.fromLTWH(x, rect.top, w, h);
      x += w;
    }
    return Rect.fromLTWH(rect.left, rect.top + h, rect.width, math.max(0, rect.height - h));
  }
}

Color treemapColor(Node n, int i) {
  if (n.synthetic) return const Color(0xFF757575);
  if (!n.isDir) return kindOf(n.name).color;
  return HSLColor.fromAHSL(1, (30 + i * 47) % 360.0, 0.45, 0.40).toColor();
}

class TreemapPainter extends CustomPainter {
  final List<TmItem> items;
  TreemapPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final r = it.rect.deflate(1);
      if (r.width <= 0 || r.height <= 0) continue;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()..color = treemapColor(it.node, i));
      if (r.width > 46 && r.height > 26) {
        final tp = TextPainter(
          text: TextSpan(
            style: const TextStyle(color: Colors.white, fontSize: 11),
            children: [
              TextSpan(
                  text: '${it.node.isDir ? '📁 ' : ''}${it.node.name}\n',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              TextSpan(text: fmtSize(it.node.size)),
            ],
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: r.width - 8);
        canvas.save();
        canvas.clipRect(r);
        tp.paint(canvas, r.topLeft + const Offset(4, 3));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant TreemapPainter old) => old.items != items;
}

TmItem? hitTreemap(List<TmItem> items, Offset p) {
  for (final it in items) {
    if (it.rect.contains(p)) return it;
  }
  return null;
}
