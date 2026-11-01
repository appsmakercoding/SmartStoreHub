import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/db.dart';
import '../core/ui.dart';
import '../core/voucher.dart';

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
  static final List<List<CartItem>> held = []; // হোল্ড করা বিল
  static int customSeq = 0;
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
      setState(() { cart.add(CartItem(id, '${p['name']}', n(p['price']), n(p['cost']), stock, unit: '${p['unit'] ?? 'পিস'}')); });
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

  Future<void> _quick() async {
    final r = await askDialog(context, 'খোলা আইটেম (বারকোড ছাড়া)', ['নাম', 'দাম (৳ প্রতি একক)', 'পরিমাণ'], init: ['', '', '1'], numeric: {1, 2});
    if (r == null || r[0].isEmpty) return;
    final price = double.tryParse(r[1]) ?? 0, qty = double.tryParse(r[2]) ?? 0;
    if (price <= 0 || qty <= 0) return;
    setState(() { cart.add(CartItem(--PosScreen.customSeq, r[0], price, 0, 1e9, qty: qty)); });
  }

  void _hold() {
    if (cart.isEmpty) {
      snack(context, 'কার্ট খালি');
      return;
    }
    setState(() {
      PosScreen.held.add(List<CartItem>.from(cart));
      cart.clear();
    });
    snack(context, 'বিল হোল্ড করা হয়েছে');
  }

  Future<void> _resume() async {
    if (PosScreen.held.isEmpty) {
      snack(context, 'কোনো হোল্ড বিল নেই');
      return;
    }
    final idx = await showDialog<int>(
      context: context,
      builder: (dc) => SimpleDialog(title: const Text('হোল্ড করা বিল'), children: [
        for (var i = 0; i < PosScreen.held.length; i++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dc, i),
            child: Text('বিল ${i + 1}: ${PosScreen.held[i].length} টি পণ্য • ${money(PosScreen.held[i].fold<double>(0, (s, c) => s + c.price * c.qty))}'),
          ),
      ]),
    );
    if (idx == null) return;
    setState(() {
      final h = PosScreen.held.removeAt(idx);
      if (cart.isNotEmpty) PosScreen.held.add(List<CartItem>.from(cart));
      cart
        ..clear()
        ..addAll(h);
    });
  }

  Future<void> _editQty(CartItem c) async {
    final r = await askDialog(context, c.name, ['পরিমাণ (${c.unit})'], init: [fmtQty(c.qty)], numeric: {0});
    final v = r == null ? null : double.tryParse(r[0]);
    if (v == null || v <= 0) return;
    if (c.id > 0 && v > c.stock) {
      if (mounted) snack(context, 'স্টক মাত্র ${fmtQty(c.stock)}');
      return;
    }
    setState(() { c.qty = v; });
  }

  Future<void> _checkout() async {
    if (cart.isEmpty) return;
    var customers = await Db.customers();
    final vatPct = double.tryParse(await Db.setting('vat_pct', '0')) ?? 0;
    final maxDisc = double.tryParse(await Db.setting('max_disc_pct', '10')) ?? 10;
    if (!mounted) return;
    final sub = subtotal;
    final disc = TextEditingController(text: '0');
    final paid = TextEditingController();
    String method = 'ক্যাশ';
    int? cust;
    final res = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (sc) => StatefulBuilder(builder: (sc, set) {
        final d = double.tryParse(disc.text) ?? 0;
        final vat = (sub - d) > 0 ? (sub - d) * vatPct / 100 : 0.0;
        final total = sub - d + vat;
        final pd = paid.text.isEmpty ? (method == 'বাকি' ? 0.0 : total) : (double.tryParse(paid.text) ?? 0);
        final due = total - pd > 0 ? total - pd : 0.0;
        Rec? cr;
        for (final c in customers) {
          if (c['id'] == cust) cr = c;
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(sc).viewInsets.bottom + 18),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('সাবটোটাল: ${money(sub)}${vat > 0 ? '  •  ভ্যাট: ${money(vat)}' : ''}', style: const TextStyle(color: Colors.black54)),
              Text('সর্বমোট: ${money(total)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: C.teal)),
              const SizedBox(height: 12),
              TextField(controller: disc, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'ডিসকাউন্ট (৳)')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final m in ['ক্যাশ', 'বিকাশ', 'Nagad', 'কার্ড', 'বাকি'])
                  ChoiceChip(label: Text(m), selected: method == m, onSelected: (_) => set(() => method = m)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: cust,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'গ্রাহক'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('সাধারণ গ্রাহক')),
                      for (final c in customers) DropdownMenuItem<int?>(value: c['id'] as int, child: Text('${c['name']} (${c['phone'] ?? ''})', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => set(() => cust = v),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'নতুন গ্রাহক',
                  icon: const Icon(Icons.person_add),
                  onPressed: () async {
                    final r = await askDialog(sc, 'নতুন গ্রাহক', ['নাম', 'মোবাইল নম্বর'], numeric: {1});
                    if (r == null) return;
                    if (r[0].isEmpty || r[1].isEmpty) {
                      if (sc.mounted) snack(sc, 'নাম ও মোবাইল নম্বর দুটোই দিন');
                      return;
                    }
                    final id = await Db.addCustomer(r[0], r[1]);
                    customers = await Db.customers();
                    set(() => cust = id);
                  },
                ),
              ]),
              if (cr != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('এখন বাকি: ${money(n(cr['due']))}${n(cr['credit_limit']) > 0 ? '  •  সীমা: ${money(n(cr['credit_limit']))}' : ''}', style: const TextStyle(fontSize: 12, color: Colors.black54))),
              const SizedBox(height: 10),
              TextField(controller: paid, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => set(() {}), decoration: InputDecoration(labelText: 'পরিশোধ (৳)', helperText: method == 'বাকি' ? 'খালি = পুরোটা বাকি' : 'খালি = সম্পূর্ণ পরিশোধ')),
              if (due > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('বাকি থাকবে: ${money(due)} (গ্রাহকের খাতায় উঠবে)', style: const TextStyle(color: C.red, fontWeight: FontWeight.bold))),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (d < 0 || d > sub) {
                      snack(sc, 'ডিসকাউন্ট সঠিক নয়');
                      return;
                    }
                    if (Session.isCashier && d > sub * maxDisc / 100) {
                      snack(sc, 'ক্যাশিয়ার সর্বোচ্চ ${fmtQty(maxDisc)}% ডিসকাউন্ট দিতে পারবে');
                      return;
                    }
                    if (due > 0.001 && cust == null) {
                      snack(sc, 'বাকি থাকলে গ্রাহক নির্বাচন করুন বা নতুন গ্রাহক (নাম+মোবাইল) যোগ করুন');
                      return;
                    }
                    if (due > 0.001 && cr != null && n(cr['credit_limit']) > 0 && n(cr['due']) + due > n(cr['credit_limit'])) {
                      snack(sc, 'গ্রাহকের বাকির সীমা পার হচ্ছে');
                      return;
                    }
                    Navigator.pop(sc, {'d': d, 'vat': vat, 'p': pd, 'm': method, 'c': cust});
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
    final cid = res['c'] as int?;
    final id = await Db.saveSale(items, res['d'] as double, res['vat'] as double, res['p'] as double, res['m'] as String, cid);
    cart.clear();
    await _search(q.text);
    final text = await saleVoucher(id);
    String? phone;
    if (cid != null) phone = '${(await Db.customer(cid))?['phone'] ?? ''}';
    if (!mounted) return;
    showVoucher(context, 'বিক্রয় সম্পন্ন ✔', text, phone: phone);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: Row(children: [
            Expanded(child: TextField(controller: q, onChanged: _search, decoration: const InputDecoration(hintText: 'পণ্যের নাম / বারকোড', prefixIcon: Icon(Icons.search), isDense: true))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), style: IconButton.styleFrom(backgroundColor: C.gold, foregroundColor: Colors.black)),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            TextButton.icon(onPressed: _quick, icon: const Icon(Icons.add_circle_outline, size: 18), label: const Text('খোলা আইটেম')),
            TextButton.icon(onPressed: _hold, icon: const Icon(Icons.pause_circle_outline, size: 18), label: const Text('হোল্ড')),
            TextButton.icon(onPressed: _resume, icon: const Icon(Icons.play_circle_outline, size: 18), label: Text('হোল্ড বিল (${PosScreen.held.length})')),
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
                subtitle: Text('স্টক: ${fmtQty(n(p['stock']))} ${p['unit'] ?? ''}', style: TextStyle(color: low ? C.red : null)),
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
                        subtitle: Text('${money(c.price)} × ${fmtQty(c.qty)} ${c.unit} = ${money(c.price * c.qty)}'),
                        trailing: SizedBox(
                          width: 150,
                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() { if (c.qty > 1) { c.qty -= 1; } else { cart.remove(c); } })),
                            InkWell(onTap: () => _editQty(c), child: Text(fmtQty(c.qty), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: () { if (c.id > 0 && c.qty + 1 > c.stock) { snack(context, 'স্টকে এর বেশি নেই'); } else { setState(() { c.qty += 1; }); } }),
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
