import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/ui.dart';

class CashCloseScreen extends StatefulWidget {
  const CashCloseScreen({super.key});
  @override
  State<CashCloseScreen> createState() => _CashState();
}

class _CashState extends State<CashCloseScreen> {
  Rec c = {};
  List<Rec> history = [];
  final actual = TextEditingController();
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.cashToday();
    final h = await Db.cashCloses();
    if (mounted) {
      setState(() {
        c = r;
        history = h;
      });
    }
  }

  Widget _r(String l, double v, {bool b = false, Color? col}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(l)), Text(money(v), style: TextStyle(fontWeight: b ? FontWeight.bold : FontWeight.normal, color: col))]),
      );

  @override
  Widget build(BuildContext context) {
    if (c.isEmpty) return const Center(child: CircularProgressIndicator());
    final exp = n(c['expected']);
    final act = double.tryParse(actual.text);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('আজকের ক্যাশ হিসাব (ড্রয়ারে থাকার কথা)', style: TextStyle(fontWeight: FontWeight.bold, color: C.teal)),
            const Divider(),
            _r('ক্যাশ বিক্রি (পরিশোধ)', n(c['cashSales'])),
            _r('(+) বাকি আদায়', n(c['collected'])),
            _r('(−) রিটার্নে নগদ ফেরত', n(c['refunds'])),
            _r('(−) দোকানের খরচ', n(c['expenses'])),
            _r('(−) সরবরাহকারীকে পরিশোধ', n(c['supplier'])),
            const Divider(),
            _r('সিস্টেম অনুযায়ী নগদ', exp, b: true),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TextField(controller: actual, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'ড্রয়ারে আসলে কত টাকা আছে (৳)')),
      if (act != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(act - exp == 0 ? 'হিসাব মিলেছে ✔' : act > exp ? 'বেশি: ${money(act - exp)}' : 'কম: ${money(exp - act)}', style: TextStyle(fontWeight: FontWeight.bold, color: act - exp == 0 ? C.teal : C.red))),
      const SizedBox(height: 10),
      TextField(controller: note, decoration: const InputDecoration(labelText: 'নোট (ঐচ্ছিক)')),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: act == null
            ? null
            : () async {
                await Db.saveCashClose(exp, act, note.text.trim());
                actual.clear();
                note.clear();
                if (mounted) snack(context, 'ক্যাশ ক্লোজিং সংরক্ষিত ✔');
                _load();
              },
        child: const Text('দিন শেষের ক্লোজিং সংরক্ষণ'),
      ),
      sectionTitle('আগের ক্লোজিং'),
      for (final h in history)
        ListTile(
          dense: true,
          title: Text('${h['day']} • সিস্টেম ${money(n(h['expected']))} • আসল ${money(n(h['actual']))}'),
          subtitle: Text('${h['uname'] ?? ''}${'${h['note'] ?? ''}'.isEmpty ? '' : ' • ${h['note']}'}'),
          trailing: Text(n(h['diff']) == 0 ? '✔' : (n(h['diff']) > 0 ? '+' : '−') + money(n(h['diff']).abs()), style: TextStyle(fontWeight: FontWeight.bold, color: n(h['diff']) == 0 ? C.teal : C.red)),
        ),
    ]);
  }
}
