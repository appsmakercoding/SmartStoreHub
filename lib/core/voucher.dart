import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'contact.dart';
import 'db.dart';
import 'ui.dart';

Future<String> _header(String title) async {
  final shop = await Db.setting('shop_name', 'SmartStoreHub');
  final ph = await Db.setting('shop_phone');
  final ad = await Db.setting('shop_address');
  final b = StringBuffer()..writeln(shop);
  if (ad.isNotEmpty) b.writeln(ad);
  if (ph.isNotEmpty) b.writeln('ফোন: $ph');
  b
    ..writeln('==========================')
    ..writeln(title);
  return b.toString();
}

Future<String> saleVoucher(int id) async {
  final s = await Db.sale(id);
  if (s == null) return '';
  final items = await Db.saleItems(id);
  final b = StringBuffer(await _header('ভাউচার নং: #$id'));
  if (s['status'] == 'cancelled') b.writeln('*** বাতিল ***');
  b
    ..writeln('তারিখ: ${dt(s['created_at'])}')
    ..writeln('ক্যাশিয়ার: ${s['uname'] ?? ''}')
    ..writeln('--------------------------');
  double sub = 0;
  for (final it in items) {
    final qy = n(it['qty']), pr = n(it['price']);
    sub += qy * pr;
    b.writeln('${it['name']}');
    b.writeln('  ${fmtQty(qy)} ${it['unit'] ?? 'পিস'} x ${pr.toStringAsFixed(0)} = ${(qy * pr).toStringAsFixed(0)}');
    if (n(it['returned_qty']) > 0) b.writeln('  (ফেরত: ${fmtQty(n(it['returned_qty']))})');
  }
  b.writeln('--------------------------');
  b.writeln('সাবটোটাল: ${money(sub)}');
  if (n(s['discount']) > 0) b.writeln('ডিসকাউন্ট: ${money(n(s['discount']))}');
  if (n(s['vat']) > 0) b.writeln('ভ্যাট: ${money(n(s['vat']))}');
  b.writeln('সর্বমোট: ${money(n(s['total']))}');
  b.writeln('পরিশোধ (${s['method']}): ${money(n(s['paid']))}');
  if (n(s['due']) > 0) b.writeln('বাকি: ${money(n(s['due']))}');
  if (s['customer_id'] != null) {
    final c = await Db.customer(s['customer_id'] as int);
    b.writeln('--------------------------');
    b.writeln('গ্রাহক: ${s['cname'] ?? ''}');
    if ('${s['cphone'] ?? ''}'.isNotEmpty) b.writeln('মোবাইল: ${s['cphone']}');
    if (c != null) b.writeln('মোট বকেয়া (এখন): ${money(n(c['due']))}');
  }
  b.writeln('==========================');
  b.writeln('ধন্যবাদ! আবার আসবেন।');
  return b.toString();
}

Future<String> collectionVoucher(Rec c, double amt, double prevDue) async {
  final b = StringBuffer(await _header('বকেয়া আদায়ের রসিদ'));
  b
    ..writeln('তারিখ: ${dt(nowIso())}')
    ..writeln('গ্রাহক: ${c['name']}')
    ..writeln('মোবাইল: ${c['phone'] ?? ''}')
    ..writeln('--------------------------')
    ..writeln('আগের বকেয়া: ${money(prevDue)}')
    ..writeln('এখন আদায়: ${money(amt)}')
    ..writeln('বর্তমান বকেয়া: ${money(prevDue - amt)}')
    ..writeln('==========================')
    ..writeln('ধন্যবাদ!');
  return b.toString();
}

Future<void> showVoucher(BuildContext context, String title, String text, {String? phone}) {
  return showDialog(
    context: context,
    builder: (dc) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
      actions: [
        TextButton.icon(icon: const Icon(Icons.share), label: const Text('শেয়ার'), onPressed: () => Share.share(text)),
        if (phone != null && phone.isNotEmpty) TextButton.icon(icon: const Icon(Icons.chat), label: const Text('WhatsApp'), onPressed: () => whatsappTo(phone, text)),
        TextButton(onPressed: () => Navigator.pop(dc), child: const Text('বন্ধ')),
      ],
    ),
  );
}
