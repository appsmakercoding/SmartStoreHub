import 'package:flutter/material.dart';
import 'db.dart';
import 'pdf_doc.dart';
import 'ui.dart';

Future<PdfDoc> _doc(String title, String sub) async => PdfDoc(await Db.setting('shop_name', 'SmartStoreHub'), title, sub);
String _stamp() => nowIso().substring(0, 10);
String _gen() => 'তৈরি: ${dt(nowIso())}';

Future<void> pdfBusinessReport(int days, {bool mine = false}) async {
  final d = DateTime.now().subtract(Duration(days: days - 1));
  final fromD = d.toIso8601String().substring(0, 10);
  final from = '${fromD}T00:00:00';
  final uid = mine ? Session.id : null;
  final p = await Db.pnl(from, uid: uid);
  final methods = await Db.methods(from, uid: uid);
  final top = await Db.topProducts(from, uid: uid);
  final doc = await _doc(mine ? 'বিক্রয় রিপোর্ট • ${Session.name}' : 'ব্যবসায়িক রিপোর্ট', 'সময়: $fromD থেকে ${_stamp()} ($days দিন) • ${_gen()}');
  doc.section('বিক্রি');
  doc.kv('বিলের সংখ্যা', '${p['count']}');
  doc.kv('মোট বিক্রি (রিটার্ন বাদে)', money(n(p['sales'])), bold: true);
  doc.kv('রিটার্ন', money(n(p['returns'])));
  doc.kv('ডিসকাউন্ট', money(n(p['discount'])));
  doc.kv('নতুন বাকি দেওয়া', money(n(p['due_given'])), color: C.red);
  doc.kv('বাকি আদায় (গ্রাহক থেকে)', money(n(p['collected'])), color: C.teal);
  if (!mine) {
    final sup = await Db.supplierPeriod(from);
    final users = await Db.perUser(from);
    final cd = await Db.totalDue();
    final sd = await Db.supplierDue();
    final net = n(p['net']);
    doc.gap();
    doc.section('লাভ-ক্ষতি');
    doc.kv('বিক্রয় লাভ (মোট)', money(n(p['gross'])));
    doc.kv('(−) দোকানের খরচ', money(n(p['expenses'])));
    doc.kv('(−) স্টক ক্ষতি (নষ্ট/মেয়াদোত্তীর্ণ/হারানো)', money(n(p['loss'])));
    doc.kv('নিট লাভ', money(net), color: net >= 0 ? C.teal : C.red, bold: true);
    doc.gap();
    doc.section('গ্রাহকের বাকি');
    doc.kv('এই সময়ে নতুন বাকি', money(n(p['due_given'])));
    doc.kv('এই সময়ে আদায়', money(n(p['collected'])));
    doc.kv('এখন মোট বাকি (সব গ্রাহক)', money(cd), color: C.red, bold: true);
    doc.gap();
    doc.section('সরবরাহকারী');
    doc.kv('এই সময়ে মাল নেওয়া', money(n(sup['bought'])));
    doc.kv('এই সময়ে পরিশোধ', money(n(sup['paid'])));
    doc.kv('এখন মোট দিতে হবে', money(sd), color: C.red, bold: true);
    doc.gap();
    doc.section('কর্মী অনুযায়ী বিক্রি');
    if (users.isEmpty) {
      doc.note('কোনো বিক্রি নেই');
    } else {
      doc.table(['কর্মী', 'বিল', 'টাকা'], [for (final u in users) ['${u['name']}', '${u['c']}', money(n(u['t']))]], widths: [4, 1, 3], right: {1, 2});
    }
  }
  doc.gap();
  doc.section('পেমেন্ট পদ্ধতি');
  if (methods.isEmpty) {
    doc.note('কোনো বিক্রি নেই');
  } else {
    doc.table(['পদ্ধতি', 'বিল', 'টাকা'], [for (final m in methods) ['${m['method']}', '${m['c']}', money(n(m['t']))]], widths: [4, 1, 3], right: {1, 2});
  }
  doc.gap();
  doc.section('সেরা বিক্রীত পণ্য');
  if (top.isEmpty) {
    doc.note('কোনো বিক্রি নেই');
  } else {
    doc.table(['পণ্য', 'পরিমাণ', 'টাকা'], [for (final x in top) ['${x['name']}', fmtQty(n(x['q'])), money(n(x['r']))]], widths: [5, 2, 3], right: {1, 2});
  }
  await doc.share('report_${_stamp()}.pdf');
}

Future<void> pdfCustomerDues() async {
  final r = await Db.customers(dueOnly: true);
  final doc = await _doc('গ্রাহকের বাকি তালিকা', _gen());
  final sum = r.fold<double>(0, (s, x) => s + n(x['due']));
  doc.kv('বাকি গ্রাহক', '${r.length} জন');
  doc.kv('মোট বাকি', money(sum), color: C.red, bold: true);
  doc.gap();
  if (r.isEmpty) {
    doc.note('কোনো বাকি নেই');
  } else {
    doc.table(['ক্র.', 'নাম', 'মোবাইল', 'বাকি'], [for (var i = 0; i < r.length; i++) ['${i + 1}', '${r[i]['name']}', '${r[i]['phone'] ?? ''}', money(n(r[i]['due']))]],
        widths: [1, 4, 3, 3], right: {3}, total: ['', 'মোট', '', money(sum)]);
  }
  await doc.share('customer_dues_${_stamp()}.pdf');
}

String _custLabel(Rec e) {
  final t = '${e['type']}';
  if (t == 'sale') return 'বিল #${e['sale_id']} (মোট ${money(n(e['total']))}, পরিশোধ ${money(n(e['paid']))})${e['status'] == 'cancelled' ? ' [বাতিল]' : ''}';
  if (t == 'cash') return 'বকেয়া আদায়';
  if (t == 'return') return 'রিটার্ন সমন্বয় (বিল #${e['sale_id']})';
  return 'বিল বাতিল (বিল #${e['sale_id']})';
}

Future<void> pdfCustomerStatement(int id) async {
  final c = await Db.customer(id);
  if (c == null) return;
  final l = await Db.customerLedger(id);
  final doc = await _doc('গ্রাহক খতিয়ান • ${c['name']}', 'মোবাইল: ${c['phone'] ?? ''} • ${_gen()}');
  doc.kv('বর্তমান বাকি', money(n(c['due'])), color: n(c['due']) > 0 ? C.red : C.teal, bold: true);
  doc.gap();
  if (l.isEmpty) {
    doc.note('কোনো লেনদেন নেই');
  } else {
    doc.table(
      ['তারিখ', 'বিবরণ', 'লেনদেন', 'চলতি বাকি'],
      [
        for (final e in l)
          [dt(e['date']), _custLabel(e), n(e['effect']) == 0 ? '—' : '${n(e['effect']) > 0 ? '+' : '−'}${money(n(e['effect']).abs())}', money(n(e['bal']))],
      ],
      widths: [3, 6, 3, 3],
      right: {2, 3},
    );
  }
  await doc.share('customer_${id}_${_stamp()}.pdf');
}

Future<void> pdfSupplierList() async {
  final r = await Db.suppliers();
  final doc = await _doc('সরবরাহকারীর হিসাব', _gen());
  final b = r.fold<double>(0, (s, x) => s + n(x['bought']));
  final p = r.fold<double>(0, (s, x) => s + n(x['paid_total']));
  final d = r.fold<double>(0, (s, x) => s + n(x['due']));
  doc.kv('মোট মাল নেওয়া', money(b));
  doc.kv('মোট পরিশোধ', money(p));
  doc.kv('মোট দিতে হবে', money(d), color: C.red, bold: true);
  doc.gap();
  if (r.isEmpty) {
    doc.note('কোনো সরবরাহকারী নেই');
  } else {
    doc.table(['সরবরাহকারী', 'মোট মাল', 'পরিশোধ', 'বাকি'], [for (final x in r) ['${x['name']}', money(n(x['bought'])), money(n(x['paid_total'])), money(n(x['due']))]],
        widths: [4, 3, 3, 3], right: {1, 2, 3}, total: ['মোট', money(b), money(p), money(d)]);
  }
  await doc.share('suppliers_${_stamp()}.pdf');
}

Future<void> pdfSupplierStatement(int id) async {
  final s = await Db.supplier(id);
  if (s == null) return;
  final l = await Db.supplierLedger(id);
  final doc = await _doc('সরবরাহকারী খতিয়ান • ${s['name']}', 'মোবাইল: ${s['phone'] ?? ''} • ${_gen()}');
  doc.kv('মোট মাল নেওয়া', money(n(s['bought'])));
  doc.kv('মোট পরিশোধ', money(n(s['paid_total'])));
  doc.kv('এখন দিতে হবে', money(n(s['due'])), color: n(s['due']) > 0 ? C.red : C.teal, bold: true);
  doc.gap();
  if (l.isEmpty) {
    doc.note('কোনো লেনদেন নেই');
  } else {
    doc.table(
      ['তারিখ', 'বিবরণ', 'টাকা', 'চলতি বাকি'],
      [
        for (final e in l)
          [
            dt(e['date']),
            e['type'] == 'purchase' ? 'ক্রয় #${e['pid']} (মোট ${money(n(e['total']))}, দিয়েছি ${money(n(e['paid']))})' : 'পরিশোধ',
            e['type'] == 'purchase' ? '+${money(n(e['effect']))}' : '−${money(n(e['amount']))}',
            money(n(e['bal'])),
          ],
      ],
      widths: [3, 6, 3, 3],
      right: {2, 3},
    );
  }
  await doc.share('supplier_${id}_${_stamp()}.pdf');
}

Future<void> pdfStockList() async {
  final r = await Db.products('');
  final doc = await _doc('স্টক তালিকা', _gen());
  final val = r.fold<double>(0, (s, x) => s + n(x['stock']) * n(x['cost']));
  doc.kv('মোট পণ্য', '${r.length} টি');
  doc.kv('মোট স্টকের মূল্য (ক্রয়মূল্যে)', money(val), bold: true);
  doc.gap();
  if (r.isEmpty) {
    doc.note('কোনো পণ্য নেই');
  } else {
    doc.table(
      ['পণ্য', 'একক', 'স্টক', 'ক্রয়', 'বিক্রয়', 'স্টক মূল্য'],
      [for (final x in r) ['${x['name']}', '${x['unit'] ?? ''}', fmtQty(n(x['stock'])), money(n(x['cost'])), money(n(x['price'])), money(n(x['stock']) * n(x['cost']))]],
      widths: [5, 1.5, 1.5, 2, 2, 2.5],
      right: {2, 3, 4, 5},
      total: ['মোট', '', '', '', '', money(val)],
    );
  }
  await doc.share('stock_${_stamp()}.pdf');
}

Future<void> pdfExpenses() async {
  final from = '${DateTime.now().subtract(const Duration(days: 29)).toIso8601String().substring(0, 10)}T00:00:00';
  final r = await Db.expenses(from);
  final doc = await _doc('দোকানের খরচ (গত ৩০ দিন)', _gen());
  final sum = r.fold<double>(0, (s, x) => s + n(x['amount']));
  doc.kv('মোট খরচ', money(sum), bold: true);
  doc.gap();
  if (r.isEmpty) {
    doc.note('কোনো খরচ নেই');
  } else {
    doc.table(['তারিখ', 'ধরন', 'নোট', 'টাকা'], [for (final x in r) [dt(x['created_at']), '${x['category']}', '${x['note'] ?? ''}', money(n(x['amount']))]],
        widths: [3, 3, 4, 3], right: {3}, total: ['', 'মোট', '', money(sum)]);
  }
  await doc.share('expenses_${_stamp()}.pdf');
}

Future<void> pdfSaleVoucher(int id) async {
  final s = await Db.sale(id);
  if (s == null) return;
  final items = await Db.saleItems(id);
  final doc = await _doc('বিক্রয় ভাউচার #$id', '${dt(s['created_at'])} • ক্যাশিয়ার: ${s['uname'] ?? ''}');
  if (s['status'] == 'cancelled') doc.note('*** এই বিল বাতিল করা হয়েছে ***');
  if (s['cname'] != null) {
    doc.kv('গ্রাহক', '${s['cname']}');
    if ('${s['cphone'] ?? ''}'.isNotEmpty) doc.kv('মোবাইল', '${s['cphone']}');
    doc.gap();
  }
  doc.table(
    ['পণ্য', 'পরিমাণ', 'দর', 'টাকা'],
    [for (final x in items) ['${x['name']}', '${fmtQty(n(x['qty']))} ${x['unit'] ?? ''}', money(n(x['price'])), money(n(x['qty']) * n(x['price']))]],
    widths: [5, 2.5, 2, 3],
    right: {1, 2, 3},
  );
  doc.gap();
  if (n(s['discount']) > 0) doc.kv('ডিসকাউন্ট', money(n(s['discount'])));
  if (n(s['vat']) > 0) doc.kv('ভ্যাট', money(n(s['vat'])));
  doc.kv('সর্বমোট', money(n(s['total'])), bold: true);
  doc.kv('পরিশোধ (${s['method']})', money(n(s['paid'])));
  if (n(s['due']) > 0) doc.kv('বাকি', money(n(s['due'])), color: C.red, bold: true);
  doc.gap();
  doc.note('ধন্যবাদ! আবার আসবেন।');
  await doc.share('voucher_$id.pdf');
}
