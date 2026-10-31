import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/ui.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SupState();
}

class _SupState extends State<SuppliersScreen> {
  List<Rec> list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.suppliers();
    if (mounted) setState(() => list = r);
  }

  Future<void> _add() async {
    final r = await askDialog(context, 'নতুন সরবরাহকারী', ['নাম / কোম্পানি', 'মোবাইল']);
    if (r == null || r[0].isEmpty) return;
    await Db.addSupplier(r[0], r[1]);
    _load();
  }

  void _menu(Rec s) => showModalBottomSheet(
        context: context,
        builder: (sc) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.add_shopping_cart, color: C.teal),
              title: const Text('নতুন ক্রয় (মাল কেনা)'),
              onTap: () async {
                Navigator.pop(sc);
                await Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseScreen(supplier: s)));
                _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments, color: C.gold),
              title: const Text('বাকি পরিশোধ করা'),
              onTap: () async {
                Navigator.pop(sc);
                final r = await askDialog(context, '${s['name']} • পাওনা ${money(n(s['due']))}', ['পরিশোধের পরিমাণ (৳)'], numeric: {0});
                final v = r == null ? null : double.tryParse(r[0]);
                if (v == null || v <= 0) return;
                await Db.paySupplier(s['id'] as int, v);
                _load();
              },
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final total = list.fold<double>(0, (s, c) => s + n(c['due']));
    return Scaffold(
      floatingActionButton: FloatingActionButton(backgroundColor: C.gold, onPressed: _add, child: const Icon(Icons.add_business)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: StatCard('সরবরাহকারীকে দিতে হবে', money(total), Icons.local_shipping, C.red)),
        Expanded(
          child: ListView(children: [
            for (final s in list)
              ListTile(
                leading: CircleAvatar(child: Text('${s['name']}'.characters.first)),
                title: Text('${s['name']}'),
                subtitle: Text('${s['phone'] ?? ''}'),
                trailing: Text(money(n(s['due'])), style: TextStyle(fontWeight: FontWeight.bold, color: n(s['due']) > 0 ? C.red : C.teal)),
                onTap: () => _menu(s),
              ),
          ]),
        ),
      ]),
    );
  }
}

class PurchaseScreen extends StatefulWidget {
  final Rec supplier;
  const PurchaseScreen({super.key, required this.supplier});
  @override
  State<PurchaseScreen> createState() => _PurState();
}

class _PurState extends State<PurchaseScreen> {
  final q = TextEditingController();
  List<Rec> results = [];
  final items = <PItem>[];
  double get total => items.fold<double>(0, (s, x) => s + x.qty * x.cost);

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String s) async {
    final r = await Db.products(s);
    if (mounted) setState(() => results = r);
  }

  Future<void> _pick(Rec p) async {
    final r = await askDialog(context, '${p['name']}', ['পরিমাণ', 'ক্রয়মূল্য (প্রতি একক)'], init: ['1', '${p['cost']}'], numeric: {0, 1});
    if (r == null) return;
    final qty = double.tryParse(r[0]) ?? 0, cost = double.tryParse(r[1]) ?? 0;
    if (qty <= 0) return;
    setState(() { items.add(PItem(p['id'] as int, '${p['name']}', qty, cost)); });
  }

  Future<void> _save() async {
    if (items.isEmpty) return;
    final r = await askDialog(context, 'মোট ${money(total)}', ['এখন পরিশোধ (৳)'], init: [total.toStringAsFixed(0)], numeric: {0});
    if (r == null) return;
    await Db.savePurchase(widget.supplier['id'] as int, items, double.tryParse(r[0]) ?? 0);
    if (!mounted) return;
    snack(context, 'ক্রয় সংরক্ষিত, স্টক বেড়েছে ✔');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('ক্রয় • ${widget.supplier['name']}')),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(10), child: TextField(controller: q, onChanged: _search, decoration: const InputDecoration(hintText: 'পণ্য খুঁজুন', prefixIcon: Icon(Icons.search), isDense: true))),
          Expanded(
            flex: 4,
            child: ListView(children: [for (final p in results) ListTile(dense: true, title: Text('${p['name']}'), subtitle: Text('স্টক ${fmtQty(n(p['stock']))}'), trailing: const Icon(Icons.add_circle, color: C.teal), onTap: () => _pick(p))]),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 4,
            child: items.isEmpty
                ? const Center(child: Text('পণ্য যোগ করুন', style: TextStyle(color: Colors.black45)))
                : ListView(children: [
                    for (final x in items)
                      ListTile(
                        dense: true,
                        title: Text(x.name),
                        subtitle: Text('${fmtQty(x.qty)} × ${money(x.cost)} = ${money(x.qty * x.cost)}'),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: C.red), onPressed: () => setState(() => items.remove(x))),
                      ),
                  ]),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).cardColor,
            child: Row(children: [
              Expanded(child: Text('মোট: ${money(total)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              ElevatedButton(onPressed: items.isEmpty ? null : _save, child: const Text('সংরক্ষণ')),
            ]),
          ),
        ]),
      );
}
