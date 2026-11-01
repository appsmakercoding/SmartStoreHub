import 'package:flutter/material.dart';
import '../core/contact.dart';
import '../core/db.dart';
import '../core/ui.dart';
import '../core/voucher.dart';

class SalesScreen extends StatefulWidget {
  final bool mine;
  const SalesScreen({super.key, this.mine = false});
  @override
  State<SalesScreen> createState() => _SalesState();
}

class _SalesState extends State<SalesScreen> {
  int days = 1;
  final q = TextEditingController();
  List<Rec> list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = DateTime.now().subtract(Duration(days: days - 1));
    final from = '${d.toIso8601String().substring(0, 10)}T00:00:00';
    final r = await Db.salesList(from, uid: widget.mine ? Session.id : null, s: q.text);
    if (mounted) setState(() => list = r);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(controller: q, onChanged: (_) => _load(), decoration: const InputDecoration(hintText: 'বিল নম্বর / গ্রাহকের নাম', prefixIcon: Icon(Icons.search), isDense: true)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SegmentedButton<int>(
            segments: const [ButtonSegment(value: 1, label: Text('আজ')), ButtonSegment(value: 7, label: Text('৭ দিন')), ButtonSegment(value: 30, label: Text('৩০ দিন'))],
            selected: {days},
            onSelectionChanged: (v) { days = v.first; _load(); },
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('কোনো বিল নেই', style: TextStyle(color: Colors.black45)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final x = list[i];
                    final cancelled = x['status'] == 'cancelled';
                    final cn = x['cname'];
                    final due = n(x['due']);
                    final extra = cn == null ? '' : ' • $cn';
                    return ListTile(
                      title: Text('#${x['id']} • ${x['method']}$extra', style: TextStyle(decoration: cancelled ? TextDecoration.lineThrough : null, color: cancelled ? Colors.grey : null)),
                      subtitle: Text('${dt(x['created_at'])} • ${x['uname'] ?? ''}${due > 0 ? ' • বাকি ${money(due)}' : ''}${cancelled ? ' • বাতিল' : ''}'),
                      trailing: Text(money(n(x['total'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () async {
                        await go(context, SaleDetailScreen(saleId: x['id'] as int));
                        _load();
                      },
                    );
                  },
                ),
        ),
      ]);
}

class SaleDetailScreen extends StatefulWidget {
  final int saleId;
  const SaleDetailScreen({super.key, required this.saleId});
  @override
  State<SaleDetailScreen> createState() => _SaleDetState();
}

class _SaleDetState extends State<SaleDetailScreen> {
  Rec? s;
  List<Rec> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.sale(widget.saleId);
    final it = await Db.saleItems(widget.saleId);
    if (mounted) {
      setState(() {
        s = r;
        items = it;
      });
    }
  }

  Future<void> _voucher() async {
    final text = await saleVoucher(widget.saleId);
    if (mounted) showVoucher(context, 'ভাউচার #${widget.saleId}', text, phone: '${s!['cphone'] ?? ''}');
  }

  Future<void> _return() async {
    final ctl = {for (final it in items) it['id'] as int: TextEditingController()};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sc) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(sc).viewInsets.bottom + 18),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('রিটার্ন: ফেরত পণ্যের পরিমাণ লিখুন', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: ctl[it['id'] as int],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '${it['name']} (সর্বোচ্চ ${fmtQty(n(it['qty']) - n(it['returned_qty']))})'),
                ),
              ),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(sc, true), child: const Text('রিটার্ন নিশ্চিত করুন'))),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    final m = <int, double>{};
    ctl.forEach((k, v) {
      final x = double.tryParse(v.text) ?? 0;
      if (x > 0) m[k] = x;
    });
    try {
      final r = await Db.returnSale(widget.saleId, m);
      await _load();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dc) => AlertDialog(
          title: const Text('রিটার্ন সম্পন্ন ✔'),
          content: Text('ফেরতের মোট মূল্য: ${money(n(r['amount']))}\nবাকি থেকে কমেছে: ${money(n(r['dueAdj']))}\nগ্রাহককে নগদ ফেরত দিন: ${money(n(r['cash']))}'),
          actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('ঠিক আছে'))],
        ),
      );
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> _cancel() async {
    final r = await askDialog(context, 'বিল বাতিল', ['বাতিলের কারণ (আবশ্যক)']);
    if (r == null || r[0].isEmpty) return;
    if (!mounted) return;
    final ok = await confirmDialog(context, 'নিশ্চিত?', 'বিল #${widget.saleId} বাতিল হবে। স্টক ফিরে আসবে ও গ্রাহকের বাকি কমবে।', yes: 'বাতিল করুন');
    if (!ok) return;
    final err = await Db.cancelSale(widget.saleId, r[0]);
    if (err != null && mounted) snack(context, err);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (s == null) return Scaffold(appBar: AppBar(title: const Text('বিল')), body: const Center(child: CircularProgressIndicator()));
    final cancelled = s!['status'] == 'cancelled';
    final due = n(s!['due']);
    return Scaffold(
      appBar: AppBar(title: Text('বিল #${widget.saleId}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (cancelled) Card(color: const Color(0xFFFFE5E5), child: ListTile(leading: const Icon(Icons.block, color: C.red), title: Text('বাতিল: ${s!['cancel_reason'] ?? ''}', style: const TextStyle(color: C.red)))),
        ListTile(dense: true, title: const Text('তারিখ'), trailing: Text(dt(s!['created_at']))),
        ListTile(dense: true, title: const Text('ক্যাশিয়ার'), trailing: Text('${s!['uname'] ?? ''}')),
        if (s!['cname'] != null) ListTile(dense: true, title: const Text('গ্রাহক'), trailing: Text('${s!['cname']} • ${s!['cphone'] ?? ''}')),
        sectionTitle('পণ্য'),
        for (final it in items)
          ListTile(
            dense: true,
            title: Text('${it['name']}'),
            subtitle: Text('${fmtQty(n(it['qty']))} ${it['unit'] ?? ''} × ${money(n(it['price']))}${n(it['returned_qty']) > 0 ? ' • ফেরত ${fmtQty(n(it['returned_qty']))}' : ''}'),
            trailing: Text(money(n(it['qty']) * n(it['price']))),
          ),
        const Divider(),
        if (n(s!['discount']) > 0) ListTile(dense: true, title: const Text('ডিসকাউন্ট'), trailing: Text(money(n(s!['discount'])))),
        if (n(s!['vat']) > 0) ListTile(dense: true, title: const Text('ভ্যাট'), trailing: Text(money(n(s!['vat'])))),
        ListTile(dense: true, title: const Text('সর্বমোট', style: TextStyle(fontWeight: FontWeight.bold)), trailing: Text(money(n(s!['total'])), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ListTile(dense: true, title: Text('পরিশোধ (${s!['method']})'), trailing: Text(money(n(s!['paid'])))),
        if (due > 0) ListTile(dense: true, title: const Text('বাকি'), trailing: Text(money(due), style: const TextStyle(color: C.red, fontWeight: FontWeight.bold))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ElevatedButton.icon(onPressed: _voucher, icon: const Icon(Icons.receipt_long), label: const Text('ভাউচার')),
          if (!cancelled) OutlinedButton.icon(onPressed: _return, icon: const Icon(Icons.assignment_return), label: const Text('রিটার্ন')),
          if (!cancelled && !Session.isCashier)
            OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: C.red), onPressed: _cancel, icon: const Icon(Icons.block), label: const Text('বিল বাতিল')),
          if ('${s!['cphone'] ?? ''}'.isNotEmpty && due > 0)
            OutlinedButton.icon(onPressed: () async { final t = await saleVoucher(widget.saleId); await whatsappTo('${s!['cphone']}', t); }, icon: const Icon(Icons.chat), label: const Text('WhatsApp')),
        ]),
      ]),
    );
  }
}
