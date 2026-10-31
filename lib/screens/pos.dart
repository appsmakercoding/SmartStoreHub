import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import '../core/db.dart';
import '../core/ui.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanState();
}

class _ScanState extends State<ScanPage> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('বারকোড স্ক্যান করুন')),
        body: MobileScanner(onDetect: (cap) {
          if (done || cap.barcodes.isEmpty) return;
          final v = cap.barcodes.first.rawValue;
          if (v == null) return;
          done = true;
          Navigator.pop(context, v);
        }),
      );
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  static final List<CartItem> cart = []; // ট্যাব বদলালেও কার্ট হারাবে না
  @override
  State<PosScreen> createState() => _PosState();
}

class _PosState extends State<PosScreen> {
  final q = TextEditingController();
  List<Rec> results = [];
  List<CartItem> get cart => PosScreen.cart;
  double get subtotal => cart.fold<double>(0, (s, c) => s + c.price * c.qty);

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String s) async {
    final r = await Db.products(s);
    if (mounted) setState(() => results = r);
  }

  void _add(Rec p) {
    final id = p['id'] as int;
    final stock = n(p['stock']);
    final ex = cart.where((c) => c.id == id).toList();
    if (ex.isNotEmpty) {
      if (ex.first.qty + 1 > stock) {
        snack(context, 'স্টকে এর বেশি নেই');
        return;
      }
      setState(() { ex.first.qty += 1; });
    } else {
      if (stock <= 0) {
        snack(context, 'স্টক নেই');
        return;
      }
      setState(() { cart.add(CartItem(id, p['name'] as String, n(p['price']), n(p['cost']), stock)); });
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code == null) return;
    final p = await Db.byBarcode(code);
    if (!mounted) return;
    if (p == null) {
      snack(context, 'বারকোড পাওয়া যায়নি: $code');
    } else {
      _add(p);
    }
  }

  Future<void> _editQty(CartItem c) async {
    final r = await askDialog(context, c.name, ['পরিমাণ'], init: [fmtQty(c.qty)], numeric: {0});
    final v = r == null ? null : double.tryParse(r[0]);
    if (v == null || v <= 0) return;
    if (v > c.stock) {
      if (mounted) snack(context, 'স্টক মাত্র ${fmtQty(c.stock)}');
      return;
    }
    setState(() { c.qty = v; });
  }

  Future<void> _checkout() async {
    if (cart.isEmpty) return;
    final customers = await Db.customers();
    if (!mounted) return;
    final sub = subtotal;
    final disc = TextEditingController(text: '0');
    final paid = TextEditingController();
    String method = 'নগদ';
    int? cust;
    final res = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (sc) => StatefulBuilder(builder: (sc, set) {
        final d = double.tryParse(disc.text) ?? 0;
        final total = sub - d;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(sc).viewInsets.bottom + 18),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('সর্বমোট: ${money(total)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: C.teal)),
              const SizedBox(height: 12),
              TextField(controller: disc, keyboardType: TextInputType.number, onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'ডিসকাউন্ট (৳)')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final m in ['নগদ', 'বিকাশ', 'নগদ (Nagad)', 'কার্ড', 'বাকি'])
                  ChoiceChip(label: Text(m), selected: method == m, onSelected: (_) => set(() => method = m)),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                value: cust,
                decoration: const InputDecoration(labelText: 'গ্রাহক'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('সাধারণ গ্রাহক')),
                  for (final c in customers) DropdownMenuItem<int?>(value: c['id'] as int, child: Text('${c['name']}')),
                ],
                onChanged: (v) => set(() => cust = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: paid, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'পরিশোধ (৳)', helperText: method == 'বাকি' ? 'খালি = পুরোটা বাকি' : 'খালি = সম্পূর্ণ পরিশোধ')),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final pd = paid.text.isEmpty ? (method == 'বাকি' ? 0.0 : total) : (double.tryParse(paid.text) ?? 0);
                    if (total - pd > 0 && cust == null) {
                      snack(sc, 'বাকি থাকলে গ্রাহক নির্বাচন করুন');
                      return;
                    }
                    Navigator.pop(sc, {'d': d, 'p': pd, 'm': method, 'c': cust});
                  },
                  child: const Text('বিল সম্পন্ন করুন'),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (res == null) return;
    final items = List<CartItem>.from(cart);
    final d = res['d'] as double, pd = res['p'] as double;
    final id = await Db.saveSale(items, d, pd, res['m'] as String, res['c'] as int?);
    final shop = await Db.setting('shop_name', 'SmartStoreHub');
    cart.clear();
    await _search(q.text);
    if (!mounted) return;
    final total = items.fold<double>(0, (s, c) => s + c.price * c.qty) - d;
    final text = _receipt(shop, id, items, d, total, pd > total ? total : pd, res['m'] as String);
    showDialog(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('বিক্রয় সম্পন্ন ✔'),
        content: SingleChildScrollView(child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        actions: [
          TextButton.icon(icon: const Icon(Icons.share), label: const Text('শেয়ার'), onPressed: () => Share.share(text)),
          TextButton(onPressed: () => Navigator.pop(dc), child: const Text('বন্ধ')),
        ],
      ),
    );
  }

  String _receipt(String shop, int id, List<CartItem> items, double disc, double total, double paid, String method) {
    final b = StringBuffer()
      ..writeln(shop)
      ..writeln('রসিদ #$id')
      ..writeln(nowIso().replaceFirst('T', ' '))
      ..writeln('ক্যাশিয়ার: ${Session.name}')
      ..writeln('--------------------------');
    for (final c in items) {
      b.writeln(c.name);
      b.writeln('  ${fmtQty(c.qty)} x ${c.price.toStringAsFixed(0)} = ${(c.qty * c.price).toStringAsFixed(0)}');
    }
    b
      ..writeln('--------------------------')
      ..writeln('ডিসকাউন্ট: ${money(disc)}')
      ..writeln('সর্বমোট: ${money(total)}')
      ..writeln('পরিশোধ ($method): ${money(paid)}')
      ..writeln('বাকি: ${money(total - paid)}')
      ..writeln('ধন্যবাদ! আবার আসবেন।');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(child: TextField(controller: q, onChanged: _search, decoration: const InputDecoration(hintText: 'পণ্যের নাম / বারকোড', prefixIcon: Icon(Icons.search), isDense: true))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), style: IconButton.styleFrom(backgroundColor: C.gold, foregroundColor: Colors.black)),
          ]),
        ),
        Expanded(
          flex: 5,
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (c, i) {
              final p = results[i];
              final low = n(p['stock']) <= n(p['min_stock']);
              return ListTile(
                dense: true,
                title: Text('${p['name']}'),
                subtitle: Text('স্টক: ${fmtQty(n(p['stock']))}', style: TextStyle(color: low ? C.red : null)),
                trailing: Text(money(n(p['price'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => _add(p),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 5,
          child: cart.isEmpty
              ? const Center(child: Text('কার্ট খালি', style: TextStyle(color: Colors.black45)))
              : ListView(children: [
                  for (final c in cart)
                    Dismissible(
                      key: ValueKey(c.id),
                      onDismissed: (_) => setState(() => cart.remove(c)),
                      background: Container(color: C.red),
                      child: ListTile(
                        dense: true,
                        title: Text(c.name),
                        subtitle: Text('${money(c.price)} × ${fmtQty(c.qty)} = ${money(c.price * c.qty)}'),
                        trailing: SizedBox(
                          width: 150,
                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() { if (c.qty > 1) { c.qty -= 1; } else { cart.remove(c); } })),
                            InkWell(onTap: () => _editQty(c), child: Text(fmtQty(c.qty), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: () { if (c.qty + 1 > c.stock) { snack(context, 'স্টকে এর বেশি নেই'); } else { setState(() { c.qty += 1; }); } }),
                          ]),
                        ),
                      ),
                    ),
                ]),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).cardColor,
          child: Row(children: [
            Expanded(child: Text('মোট: ${money(subtotal)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            ElevatedButton.icon(onPressed: cart.isEmpty ? null : _checkout, icon: const Icon(Icons.payments), label: const Text('পেমেন্ট')),
          ]),
        ),
      ]);
}
