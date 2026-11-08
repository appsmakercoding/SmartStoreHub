import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'ui.dart';

enum _K { section, kv, th, td, gap, note }

class _Row {
  final _K k;
  final List<String> c;
  final List<double> w;
  final Set<int> right;
  final bool bold;
  final Color? color;
  final bool shade;
  final _Row? head;
  _Row(this.k, this.c, {this.w = const [], this.right = const {}, this.bold = false, this.color, this.shade = false, this.head});
}

/// বাংলা লেখা সঠিকভাবে দেখানোর জন্য প্রতিটি পাতা Flutter-এর টেক্সট ইঞ্জিনে ছবি করে PDF-এ বসানো হয়
class PdfDoc {
  final String shop, title, subtitle;
  final List<_Row> _rows = [];
  PdfDoc(this.shop, this.title, this.subtitle);

  static const double _w = 1240, _h = 1754, _m = 70;

  void section(String t) => _rows.add(_Row(_K.section, [t]));
  void note(String t) => _rows.add(_Row(_K.note, [t]));
  void gap() => _rows.add(_Row(_K.gap, const []));
  void kv(String k, String v, {Color? color, bool bold = false}) =>
      _rows.add(_Row(_K.kv, [k, v], w: const [3, 2], right: const {1}, bold: bold, color: color));

  void table(List<String> head, List<List<String>> data, {List<double>? widths, Set<int> right = const {}, List<String>? total}) {
    final w = widths ?? List<double>.filled(head.length, 1);
    final h = _Row(_K.th, head, w: w, right: right, bold: true);
    _rows.add(h);
    for (var i = 0; i < data.length; i++) {
      _rows.add(_Row(_K.td, data[i], w: w, right: right, shade: i.isOdd, head: h));
    }
    if (total != null) _rows.add(_Row(_K.td, total, w: w, right: right, bold: true, shade: true, head: h));
  }

  TextPainter _tp(String t, double w, double size, {bool bold = false, Color color = const Color(0xFF222222), TextAlign align = TextAlign.left}) {
    final p = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    );
    p.layout(minWidth: w, maxWidth: w);
    return p;
  }

  Future<List<Uint8List>> _render() async {
    final pages = <Uint8List>[];
    late ui.PictureRecorder rec;
    late Canvas cv;
    double y = _m;
    var pageNo = 0;
    const cw = _w - 2 * _m;

    void start() {
      pageNo++;
      rec = ui.PictureRecorder();
      cv = Canvas(rec, Rect.fromLTWH(0, 0, _w, _h));
      cv.drawRect(Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);
      y = _m;
    }

    Future<void> finish() async {
      final f = _tp('SmartStoreHub • Powered by Hasan        পাতা $pageNo', cw, 20, color: const Color(0xFF888888), align: TextAlign.right);
      f.paint(cv, Offset(_m, _h - _m + 8));
      final pic = rec.endRecording();
      final img = await pic.toImage(_w.toInt(), _h.toInt());
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      pages.add(bd!.buffer.asUint8List());
    }

    Future<void> place(_Row r) async {
      if (r.k == _K.gap) {
        y += 20;
        return;
      }
      final size = r.k == _K.section ? 30.0 : (r.k == _K.kv ? 26.0 : (r.k == _K.note ? 22.0 : 24.0));
      final ps = <TextPainter>[];
      final xs = <double>[];
      double h = 0;
      if (r.k == _K.section || r.k == _K.note) {
        final p = _tp(r.c[0], cw, size, bold: r.k == _K.section, color: r.k == _K.section ? C.teal : const Color(0xFF666666));
        ps.add(p);
        xs.add(_m);
        h = p.height;
      } else {
        final sum = r.w.fold<double>(0, (a, b) => a + b);
        double x = _m;
        for (var i = 0; i < r.c.length; i++) {
          final colW = cw * r.w[i] / sum;
          final col = r.k == _K.th ? C.dark : ((i == r.c.length - 1 && r.color != null) ? r.color! : const Color(0xFF222222));
          final p = _tp(r.c[i], colW - 20, size, bold: r.bold || r.k == _K.th, color: col, align: r.right.contains(i) ? TextAlign.right : TextAlign.left);
          ps.add(p);
          xs.add(x + 10);
          x += colW;
          if (p.height > h) h = p.height;
        }
      }
      final pad = r.k == _K.section ? 12.0 : 11.0;
      final extraTop = r.k == _K.section ? 14.0 : 0.0;
      final total = h + pad * 2 + extraTop;
      if (y + total > _h - _m - 20) {
        await finish();
        start();
        if (r.head != null) await place(r.head!);
      }
      if (r.k == _K.th) {
        cv.drawRect(Rect.fromLTWH(_m, y, cw, total), Paint()..color = const Color(0xFFDDEFE8));
      } else if (r.k == _K.td && r.shade) {
        cv.drawRect(Rect.fromLTWH(_m, y, cw, total), Paint()..color = const Color(0xFFF1F6F4));
      }
      for (var i = 0; i < ps.length; i++) {
        ps[i].paint(cv, Offset(xs[i], y + pad + extraTop));
      }
      if (r.k == _K.section) {
        cv.drawRect(Rect.fromLTWH(_m, y + total - 3, cw, 2), Paint()..color = C.teal);
      }
      y += total;
    }

    start();
    final hs = _tp(shop, cw, 44, bold: true, color: C.teal);
    hs.paint(cv, Offset(_m, y));
    y += hs.height + 6;
    final ht = _tp(title, cw, 34, bold: true);
    ht.paint(cv, Offset(_m, y));
    y += ht.height + 4;
    final hsub = _tp(subtitle, cw, 22, color: const Color(0xFF777777));
    hsub.paint(cv, Offset(_m, y));
    y += hsub.height + 12;
    cv.drawRect(Rect.fromLTWH(_m, y, cw, 4), Paint()..color = C.gold);
    y += 22;

    for (final r in _rows) {
      await place(r);
    }
    await finish();
    return pages;
  }

  Future<File> save(String fileName) async {
    final pages = await _render();
    final doc = pw.Document();
    for (final b in pages) {
      final img = pw.MemoryImage(b);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context c) => pw.Image(img, width: PdfPageFormat.a4.width, height: PdfPageFormat.a4.height, fit: pw.BoxFit.fill),
      ));
    }
    final f = File('${Directory.systemTemp.path}/$fileName');
    await f.writeAsBytes(await doc.save());
    return f;
  }

  Future<void> share(String fileName) async {
    final f = await save(fileName);
    await Share.shareXFiles([XFile(f.path)], text: title);
  }
}
