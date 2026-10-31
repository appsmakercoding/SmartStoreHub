import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/ui.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsState();
}

class _ProductsState extends State<ProductsScreen> {
  List<Rec> list = [];
  final q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.products(q.text);
    if (mounted) setState(() => list = r);
  }

  Future<void> _edit([Rec? p]) async {
    final r = await askDialog(
      context,
      p == null ? 'নতুন পণ্য (মালামাল এন্ট্রি)' : 'পণ্য সম্পাদনা',
      ['নাম', 'বারকোড (খালি = অটো তৈরি)', 'ক্যাটাগরি', 'ক্রয়মূল্য', 'বিক্রয়মূল্য', 'স্টক', 'সর্বনিম্ন স্টক', 'মেয়াদ (YYYY-MM-DD, ঐচ্ছিক)'],
      init: p == null ? null : ['${p['name']}', '${p['barcode'] ?? ''}', '${p['category'] ?? ''}', '${p['cost']}', '${p['price']}', '${p['stock']}', '${p['min_stock']}', '${p['expiry'] ?? ''}'],
      numeric: {3, 4, 5, 6},
    );
    if (r == null || r[0].isEmpty) return;
    await Db.saveProduct({
      'name': r[0],
      'barcode': r[1].isEmpty ? genBarcode() : r[1],
      'category': r[2],
      'cost': double.tryParse(r[3]) ?? 0,
      'price': double.tryParse(r[4]) ?? 0,
      'stock': double.tryParse(r[5]) ?? 0,
      'min_stock': double.tryParse(r[6]) ?? 5,
      'expiry': r[7],
    }, p?['id'] as int?);
    _load();
  }

  void _label(Rec p) => showDialog(
        context: context,
        builder: (dc) => AlertDialog(
          title: Text('${p['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            BarcodeWidget(barcode: Barcode.code128(), data: '${p['barcode']}', width: 240, height: 90),
            const SizedBox(height: 8),
            Text(money(n(p['price'])), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('বন্ধ'))],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(backgroundColor: C.gold, onPressed: _edit, child: const Icon(Icons.add)),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(controller: q, onChanged: (_) => _load(), decoration: const InputDecoration(hintText: 'পণ্য খুঁজুন', prefixIcon: Icon(Icons.search), isDense: true)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (c, i) {
                final p = list[i];
                final low = n(p['stock']) <= n(p['min_stock']);
                return ListTile(
                  leading: CircleAvatar(backgroundColor: (low ? C.red : C.teal).withAlpha(30), child: Icon(Icons.inventory_2, color: low ? C.red : C.teal)),
                  title: Text('${p['name']}'),
                  subtitle: Text('স্টক ${fmtQty(n(p['stock']))} • ${p['barcode'] ?? ''}${(p['expiry'] ?? '') != '' ? ' • মেয়াদ ${p['expiry']}' : ''}', style: TextStyle(color: low ? C.red : null, fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(n(p['price'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.qr_code), onPressed: () => _label(p)),
                    if (Session.role != 'cashier') IconButton(icon: const Icon(Icons.delete_outline, color: C.red), onPressed: () async { await Db.deleteProduct(p['id'] as int); _load(); }),
                  ]),
                  onTap: () => _edit(p),
                );
              },
            ),
          ),
        ]),
      );
}
