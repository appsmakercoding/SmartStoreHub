import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/ui.dart';
import 'sales.dart';

class ReportsScreen extends StatefulWidget {
  final bool mine; // ক্যাশিয়ার শুধু নিজের হিসাব দেখবে
  const ReportsScreen({super.key, this.mine = false});
  @override
  State<ReportsScreen> createState() => _RepState();
}

class _RepState extends State<ReportsScreen> {
  int days = 1;
  Rec p = {}, sup = {};
  List<Rec> methods = [], top = [], users = [];
  double custDue = 0, supDue = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = DateTime.now().subtract(Duration(days: days - 1));
    final from = '${d.toIso8601String().substring(0, 10)}T00:00:00';
    final uid = widget.mine ? Session.id : null;
    final pnl = await Db.pnl(from, uid: uid);
    final m = await Db.methods(from, uid: uid);
    final t = await Db.topProducts(from, uid: uid);
    final u = widget.mine ? <Rec>[] : await Db.perUser(from);
    final sp = widget.mine ? <String, Object?>{} : await Db.supplierPeriod(from);
    final cd = widget.mine ? 0.0 : await Db.totalDue();
    final sd = widget.mine ? 0.0 : await Db.supplierDue();
    if (!mounted) return;
    setState(() {
      p = pnl;
      methods = m;
      top = t;
      users = u;
      sup = sp;
      custDue = cd;
      supDue = sd;
    });
  }

  Widget _card(String title, List<Widget> rows) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: C.teal, fontSize: 15)),
            const Divider(),
            ...rows,
          ]),
        ),
      );

  Widget _r(String l, String v, {Color? c, bool b = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(l)), Text(v, style: TextStyle(fontWeight: b ? FontWeight.bold : FontWeight.normal, color: c))]),
      );

  @override
  Widget build(BuildContext context) {
    if (p.isEmpty) return const Center(child: CircularProgressIndicator());
    final net = n(p['net']);
    return ListView(padding: const EdgeInsets.all(12), children: [
      SegmentedButton<int>(
        segments: const [ButtonSegment(value: 1, label: Text('আজ')), ButtonSegment(value: 7, label: Text('৭ দিন')), ButtonSegment(value: 30, label: Text('৩০ দিন'))],
        selected: {days},
        onSelectionChanged: (v) { days = v.first; _load(); },
      ),
      _card('বিক্রি', [
        _r('বিলের সংখ্যা', '${p['count']}'),
        _r('মোট বিক্রি (রিটার্ন বাদে)', money(n(p['sales'])), b: true),
        _r('রিটার্ন', money(n(p['returns']))),
        _r('ডিসকাউন্ট', money(n(p['discount']))),
        _r('নতুন বাকি দেওয়া', money(n(p['due_given'])), c: C.red),
        _r('বাকি আদায় (গ্রাহক থেকে)', money(n(p['collected'])), c: C.teal),
      ]),
      if (!widget.mine) ...[
        _card('লাভ-ক্ষতি', [
          _r('বিক্রয় লাভ (মোট)', money(n(p['gross']))),
          _r('(−) দোকানের খরচ', money(n(p['expenses']))),
          _r('(−) স্টক ক্ষতি (নষ্ট/মেয়াদোত্তীর্ণ/হারানো)', money(n(p['loss']))),
          const Divider(),
          _r('নিট লাভ', money(net), c: net >= 0 ? C.teal : C.red, b: true),
        ]),
        _card('গ্রাহকের বাকি', [
          _r('এই সময়ে নতুন বাকি', money(n(p['due_given']))),
          _r('এই সময়ে আদায়', money(n(p['collected']))),
          _r('এখন মোট বাকি (সব গ্রাহক)', money(custDue), c: C.red, b: true),
        ]),
        _card('সরবরাহকারী', [
          _r('এই সময়ে মাল নেওয়া', money(n(sup['bought']))),
          _r('এই সময়ে পরিশোধ', money(n(sup['paid']))),
          _r('এখন মোট দিতে হবে', money(supDue), c: C.red, b: true),
        ]),
      ],
      _card('পেমেন্ট পদ্ধতি', [
        if (methods.isEmpty) const Text('কোনো বিক্রি নেই', style: TextStyle(color: Colors.black45)),
        for (final m in methods) _r('${m['method']} (${m['c']} বিল)', money(n(m['t']))),
      ]),
      _card('সেরা বিক্রীত পণ্য', [
        if (top.isEmpty) const Text('কোনো বিক্রি নেই', style: TextStyle(color: Colors.black45)),
        for (final x in top) _r('${x['name']} (${fmtQty(n(x['q']))})', money(n(x['r']))),
      ]),
      if (!widget.mine)
        _card('কর্মী অনুযায়ী বিক্রি', [
          if (users.isEmpty) const Text('কোনো বিক্রি নেই', style: TextStyle(color: Colors.black45)),
          for (final u in users) _r('${u['name']} (${u['c']} বিল)', money(n(u['t']))),
        ]),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => go(context, Scaffold(appBar: AppBar(title: const Text('বিল তালিকা')), body: SalesScreen(mine: widget.mine))),
        icon: const Icon(Icons.list_alt),
        label: const Text('সব বিল দেখুন'),
      ),
    ]);
  }
}
