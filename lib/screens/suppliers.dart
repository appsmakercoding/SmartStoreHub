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

  @override
  Widget build(BuildContext context) {
    final bought = list.fold<double>(0, (s, c) => s + n(c['bought']));
    final paid = list.fold<double>(0, (s, c) => s + n(c['paid_total']));
    final due = list.fold<double>(0, (s, c) => s + n(c['due']));
    return Scaffold(
      floatingActionButton: FloatingActionButton(backgroundColor: C.gold, onPressed: _add, child: const Icon(Icons.add_business)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: Row(children: [
            Expanded(child: StatCard('মোট মাল নেওয়া', money(bought), Icons.local_shipping, C.teal)),
            const SizedBox(width: 8),
            Expanded(child: StatCard('মোট পরিশোধ', money(paid), Icons.payments, const Color(0xFF2E7D32))),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(10), child: StatCard('মোট দিতে হবে (বাকি)', money(due), Icons.account_balance_wallet, C.red)),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('কোনো সরবরাহকারী নেই', style: TextStyle(color: Colors.black45)))
              : ListView(children: [
                  for (final s in list)
                    ListTile(
                      leading: CircleAvatar(child: Text('${s['name']}'.characters.first)),
                      title: Text('${s['name']}'),
                      subtitle: Text('মাল ${money(n(s['bought']))} • পরিশোধ ${money(n(s['paid_total']))}'),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(money(n(s['due'])), style: TextStyle(fontWeight: FontWeight.bold, color: n(s['due']) > 0 ? C.red : C.teal)),
                        const Text('বাকি', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      ]),
                      onTap: () async {
                        await go(context, SupplierDetailScreen(supplierId: s['id'] as int));
                        _load();
                      },
                    ),
                ]),
        ),
      ]),
    );
  }
}

class SupplierDetailScreen extends StatefulWidget {
  final int supplierId;
  const SupplierDetailScreen({super.key, required this.supplierId});
  @override
  State<SupplierDetailScreen> createState() => _SupDetState();
}

class _SupDetState extends State<SupplierDetailScreen> {
  Rec? s;
  List<Rec> ledger = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.supplier(widget.supplierId);
    final l = await Db.supplierLedger(widget.supplierId);
    if (mounted) {
      setState(() {
        s = r;
        ledger = l.reversed.toList();
      });
    }
  }

  Future<void> _pay() async {
    final due = n(s!['due']);
    final r = await askDialog(context, '${s!['name']} • পাওনা ${money(due)}', ['পরিশোধের পরিমাণ (৳)'], init: [due.toStringAsFixed(0)], numeric: {0});
    final v = r == null ? null : double.tryParse(r[0]);
    if (v == null || v <= 0) return;
    if (v > due + 0.001) {
      if (mounted) snack(context, 'বাকির চেয়ে বেশি দেওয়া যাবে না');
      return;
    }
    await Db.paySupplier(widget.supplierId, v);
    _load();
  }

  Future<void> _items(int pid) async {
    final items = await Db.purchaseItems(pid);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text('ক্রয় #$pid'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final x in items) Text('${x['name']}: ${fmtQty(n(x['qty']))} × ${money(n(x['cost']))} = ${money(n(x['qty']) * n(x['cost']))}'),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('বন্ধ'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (s == null) return Scaffold(appBar: AppBar(title: const Text('সরবরাহকারী')), body: const Center(child: CircularProgressIndicator()));
    final due = n(s!['due']);
    return Scaffold(
      appBar: AppBar(title: Text('${s!['name']}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(child: StatCard('মোট মাল', money(n(s!['bought'])), Icons.local_shipping, C.teal)),
          const SizedBox(width: 8),
          Expanded(child: StatCard('মোট পরিশোধ', money(n(s!['paid_total'])), Icons.payments, const Color(0xFF2E7D32))),
        ]),
        const SizedBox(height: 8),
        StatCard('এখন দিতে হবে', money(due), Icons.account_balance_wallet, due > 0 ? C.red : C.teal),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ElevatedButton.icon(
            onPressed: () async {
              await go(context, PurchaseScreen(supplier: s!));
              _load();
            },
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('নতুন ক্রয়'),
          ),
          if (due > 0) OutlinedButton.icon(onPressed: _pay, icon: const Icon(Icons.payments), label: const Text('পরিশোধ করুন')),
        ]),
        sectionTitle('খতিয়ান'),
        if (ledger.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('কোনো লেনদেন নেই', style: TextStyle(color: Colors.black45))),
        for (final e in ledger)
          ListTile(
            dense: true,
            title: Text(e['type'] == 'purchase' ? 'ক্রয় • মোট ${money(n(e['total']))}' : 'পরিশোধ ${money(n(e['amount']))}'),
            subtitle: Text(e['type'] == 'purchase' ? '${dt(e['date'])} • দিয়েছি ${money(n(e['paid']))}' : dt(e['date'])),
            trailing: Text('বাকি ${money(n(e['bal']))}', style: const TextStyle(fontSize: 12)),
            onTap: e['type'] == 'purchase' ? () => _items(e['pid'] as int) : null,
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
