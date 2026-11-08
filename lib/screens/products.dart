import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/ui.dart';
import 'scanner.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsState();
}

class _ProductsState extends State<ProductsScreen> {
  List<Rec> list = [];
  Rec stats = {};
  String filter = 'all'; // all | low | exp | bin
  final q = TextEditingController();
  bool get canManage => !Session.isCashier;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = filter == 'bin' ? await Db.deletedProducts() : await Db.products(q.text, filter);
    final s = await Db.productStats();
    if (mounted) {
      setState(() {
        list = r;
        stats = s;
      });
    }
  }

  Future<void> _edit([Rec? p]) async {
    final r = await askDialog(
      context,
      p == null ? 'নতুন পণ্য (মালামাল এন্ট্রি)' : 'পণ্য সম্পাদনা',
      ['নাম', 'বারকোড (খালি = অটো তৈরি)', 'ক্যাটাগরি', 'একক (পিস/কেজি/লিটার/ডজন)', 'ক্রয়মূল্য (প্রতি একক)', 'বিক্রয়মূল্য (প্রতি একক)', 'স্টক', 'সর্বনিম্ন স্টক (সতর্কতা)', 'মেয়াদ (YYYY-MM-DD, ঐচ্ছিক)'],
      init: p == null
          ? ['', '', '', 'পিস', '', '', '', '5', '']
          : ['${p['name']}', '${p['barcode'] ?? ''}', '${p['category'] ?? ''}', '${p['unit'] ?? 'পিস'}', '${p['cost']}', '${p['price']}', '${p['stock']}', '${p['min_stock']}', '${p['expiry'] ?? ''}'],
      numeric: {4, 5, 6, 7},
      scanFields: {1},
      scan: () => scanOnce(context),
    );
    if (r == null || r[0].isEmpty) return;
    final err = await Db.saveProduct({
      'name': r[0],
      'barcode': r[1].isEmpty ? genBarcode() : r[1],
      'category': r[2],
      'unit': r[3].isEmpty ? 'পিস' : r[3],
      'cost': double.tryParse(r[4]) ?? 0,
      'price': double.tryParse(r[5]) ?? 0,
      'stock': double.tryParse(r[6]) ?? 0,
      'min_stock': double.tryParse(r[7]) ?? 5,
      'expiry': r[8],
    }, p?['id'] as int?);
    if (err != null && mounted) snack(context, err);
    _load();
  }

  Future<void> _adjust(Rec p) async {
    bool dec = true;
    String reason = 'নষ্ট';
    final qty = TextEditingController();
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sc) => StatefulBuilder(builder: (sc, set) {
        final reasons = dec ? ['নষ্ট', 'মেয়াদোত্তীর্ণ', 'চুরি/হারানো', 'গণনার ভুল', 'অন্যান্য'] : ['গণনার ভুল', 'প্রাপ্তি', 'অন্যান্য'];
        if (!reasons.contains(reason)) reason = reasons.first;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(sc).viewInsets.bottom + 18),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('স্টক সমন্বয়: ${p['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Text('বর্তমান স্টক: ${fmtQty(n(p['stock']))} ${p['unit'] ?? ''}'),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('কমানো')), ButtonSegment(value: false, label: Text('বাড়ানো'))],
                selected: {dec},
                onSelectionChanged: (v) => set(() => dec = v.first),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [for (final r in reasons) ChoiceChip(label: Text(r), selected: reason == r, onSelected: (_) => set(() => reason = r))]),
              const SizedBox(height: 12),
              TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'পরিমাণ')),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final v = double.tryParse(qty.text) ?? 0;
                    if (v <= 0) {
                      snack(sc, 'পরিমাণ লিখুন');
                      return;
                    }
                    if (dec && v > n(p['stock'])) {
                      snack(sc, 'স্টকের চেয়ে বেশি কমানো যাবে না');
                      return;
                    }
                    Navigator.pop(sc, true);
                  },
                  child: const Text('সংরক্ষণ'),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (done != true) return;
    final v = double.parse(qty.text);
    await Db.adjustStock(p['id'] as int, '${p['name']}', dec ? -v : v, n(p['cost']), reason);
    _load();
  }

  Future<void> _detail(Rec p) async {
    final low = n(p['stock']) <= n(p['min_stock']);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sc) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if ('${p['barcode'] ?? ''}'.isNotEmpty) Center(child: BarcodeWidget(barcode: Barcode.code128(), data: '${p['barcode']}', width: 240, height: 70)),
            const SizedBox(height: 10),
            _row('বিক্রয়মূল্য', '${money(n(p['price']))} / ${p['unit'] ?? 'পিস'}'),
            if (canManage) _row('ক্রয়মূল্য', money(n(p['cost']))),
            if (canManage) _row('প্রতি একক লাভ', money(n(p['price']) - n(p['cost']))),
            _row('স্টক', '${fmtQty(n(p['stock']))} ${p['unit'] ?? ''}', color: low ? C.red : null),
            _row('সর্বনিম্ন স্টক', fmtQty(n(p['min_stock']))),
            if ('${p['category'] ?? ''}'.isNotEmpty) _row('ক্যাটাগরি', '${p['category']}'),
            if ('${p['expiry'] ?? ''}'.isNotEmpty) _row('মেয়াদ', '${p['expiry']}'),
            if (canManage) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(onPressed: () { Navigator.pop(sc); _edit(p); }, icon: const Icon(Icons.edit), label: const Text('সম্পাদনা')),
                ElevatedButton.icon(onPressed: () { Navigator.pop(sc); _adjust(p); }, icon: const Icon(Icons.tune), label: const Text('স্টক সমন্বয়')),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: C.red),
                  onPressed: () async {
                    Navigator.pop(sc);
                    final ok = await confirmDialog(context, 'পণ্য মুছবেন?', '"${p['name']}" (স্টক ${fmtQty(n(p['stock']))}) রিসাইকেল বিনে যাবে। পরে ফেরত আনা যাবে।', yes: 'মুছুন');
                    if (!ok) return;
                    await Db.deleteProduct(p['id'] as int, '${p['name']}');
                    _load();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('মুছুন'),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _row(String l, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(l)), Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: color))]),
      );

  Widget _chip(String label, String f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: filter == f, onSelected: (_) { filter = f; _load(); }),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: filter == 'bin' ? null : FloatingActionButton(backgroundColor: C.gold, onPressed: _edit, child: const Icon(Icons.add)),
        body: Column(children: [
          if (stats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Row(children: [
                Expanded(child: StatCard('মোট পণ্য', '${stats['c']}', Icons.inventory_2, C.teal)),
                const SizedBox(width: 8),
                Expanded(child: StatCard('স্টক কম', '${stats['low']}', Icons.warning_amber, C.red)),
              ]),
            ),
          if (stats.isNotEmpty && canManage) Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 0), child: StatCard('মোট স্টকের মূল্য (ক্রয়মূল্যে)', money(n(stats['v'])), Icons.warehouse, const Color(0xFF1565C0))),
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(controller: q, onChanged: (_) => _load(), decoration: InputDecoration(
              hintText: 'পণ্য খুঁজুন (নাম/বারকোড)',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'স্ক্যান করে খুঁজুন',
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () async {
                  final code = await scanOnce(context);
                  if (code != null) {
                    q.text = code;
                    _load();
                  }
                },
              ),
            )),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [_chip('সব', 'all'), _chip('স্টক কম', 'low'), _chip('মেয়াদ কাছে', 'exp'), if (canManage) _chip('🗑 রিসাইকেল বিন', 'bin')]),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('কোনো পণ্য নেই', style: TextStyle(color: Colors.black45)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final p = list[i];
                      final low = n(p['stock']) <= n(p['min_stock']);
                      if (filter == 'bin') {
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.delete_outline)),
                          title: Text('${p['name']}'),
                          subtitle: Text('স্টক ছিল ${fmtQty(n(p['stock']))}'),
                          trailing: TextButton(onPressed: () async { await Db.restoreProduct(p['id'] as int); _load(); }, child: const Text('ফেরত আনুন')),
                        );
                      }
                      final exp = '${p['expiry'] ?? ''}';
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: (low ? C.red : C.teal).withAlpha(30), child: Icon(Icons.inventory_2, color: low ? C.red : C.teal)),
                        title: Text('${p['name']}'),
                        subtitle: Text('স্টক ${fmtQty(n(p['stock']))} ${p['unit'] ?? ''}${exp.isEmpty ? '' : ' • মেয়াদ $exp'}', style: TextStyle(color: low ? C.red : null, fontSize: 12)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(money(n(p['price'])), style: const TextStyle(fontWeight: FontWeight.bold)), const Icon(Icons.chevron_right)]),
                        onTap: () => _detail(p),
                      );
                    },
                  ),
          ),
        ]),
      );
}
