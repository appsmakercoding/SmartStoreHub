import 'dart:convert';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'db.dart';
import 'ui.dart';

String _esc(Object? v) {
  final s = '${v ?? ''}';
  return (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
}

Future<void> _share(String name, List<List<Object?>> rows) async {
  final b = StringBuffer('\uFEFF'); // Excel-এ বাংলা ঠিক দেখানোর জন্য
  for (final r in rows) {
    b.writeln(r.map(_esc).join(','));
  }
  final f = File('${Directory.systemTemp.path}/$name');
  await f.writeAsString(b.toString(), encoding: utf8);
  await Share.shareXFiles([XFile(f.path)], text: name);
  await Db.log('এক্সপোর্ট: $name');
}

/// kind: sales | dues | products | suppliers | expenses
Future<void> exportCsv(String kind) async {
  final day = nowIso().substring(0, 10);
  final from = '${DateTime.now().subtract(const Duration(days: 29)).toIso8601String().substring(0, 10)}T00:00:00';
  if (kind == 'sales') {
    final r = await Db.q(
        'SELECT s.*, u.name uname, c.name cname FROM sales s LEFT JOIN users u ON u.id=s.user_id LEFT JOIN customers c ON c.id=s.customer_id WHERE s.branch_id=? AND s.created_at>=? ORDER BY s.id',
        [Session.branch, from]);
    await _share('বিক্রি_$day.csv', [
      ['বিল নং', 'তারিখ', 'ক্যাশিয়ার', 'গ্রাহক', 'পদ্ধতি', 'ডিসকাউন্ট', 'ভ্যাট', 'মোট', 'পরিশোধ', 'বাকি', 'অবস্থা'],
      for (final x in r) [x['id'], dt(x['created_at']), x['uname'], x['cname'], x['method'], x['discount'], x['vat'], x['total'], x['paid'], x['due'], x['status'] == 'cancelled' ? 'বাতিল' : 'ঠিক'],
    ]);
  } else if (kind == 'dues') {
    final r = await Db.customers(dueOnly: true);
    await _share('গ্রাহকের_বাকি_$day.csv', [
      ['নাম', 'মোবাইল', 'বাকি', 'বাকির সীমা'],
      for (final x in r) [x['name'], x['phone'], x['due'], x['credit_limit']],
    ]);
  } else if (kind == 'products') {
    final r = await Db.products('');
    await _share('পণ্য_তালিকা_$day.csv', [
      ['নাম', 'বারকোড', 'ক্যাটাগরি', 'একক', 'ক্রয়মূল্য', 'বিক্রয়মূল্য', 'স্টক', 'মেয়াদ'],
      for (final x in r) [x['name'], x['barcode'], x['category'], x['unit'], x['cost'], x['price'], x['stock'], x['expiry']],
    ]);
  } else if (kind == 'suppliers') {
    final r = await Db.suppliers();
    await _share('সরবরাহকারী_$day.csv', [
      ['নাম', 'মোবাইল', 'মোট মাল', 'মোট পরিশোধ', 'বাকি'],
      for (final x in r) [x['name'], x['phone'], x['bought'], x['paid_total'], x['due']],
    ]);
  } else {
    final r = await Db.expenses(from);
    await _share('খরচ_$day.csv', [
      ['তারিখ', 'ধরন', 'টাকা', 'নোট', 'কে'],
      for (final x in r) [dt(x['created_at']), x['category'], x['amount'], x['note'], x['uname']],
    ]);
  }
}
