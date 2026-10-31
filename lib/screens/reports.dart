import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/ui.dart';

class ReportsScreen extends StatefulWidget {
  final bool mine; // ক্যাশিয়ার শুধু নিজের হিসাব দেখবে
  const ReportsScreen({super.key, this.mine = false});
  @override
  State<ReportsScreen> createState() => _RepState();
}

class _RepState extends State<ReportsScreen> {
  int days = 1;
  Rec s = {};
  List<Rec> methods = [], top = [], users = [], recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = DateTime.now().subtract(Duration(days: days - 1));
    final from = '${d.toIso8601String().substring(0, 10)}T00:00:00';
    final uid = widget.mine ? Session.id : null;
    final r = await Future.wait([
      Db.summary(from, uid: uid),
      Db.methods(from, uid: uid),
      Db.topProducts(from, uid: uid),
      widget.mine ? Future.value(<Rec>[]) : Db.perUser(from),
      Db.recent(from, uid: uid),
    ]);
    if (!mounted) return;
    setState(() {
      s = r[0] as Rec;
      methods = r[1] as List<Rec>;
      top = r[2] as List<Rec>;
      users = r[3] as List<Rec>;
      recent = r[4] as List<Rec>;
    });
  }

  Widget _h(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)));

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 1, label: Text('আজ')), ButtonSegment(value: 7, label: Text('৭ দিন')), ButtonSegment(value: 30, label: Text('৩০ দিন'))],
          selected: {days},
          onSelectionChanged: (v) { days = v.first; _load(); },
        ),
        const SizedBox(height: 12),
        if (s.isNotEmpty)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.7,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              StatCard('মোট বিক্রি', money(n(s['t'])), Icons.shopping_cart, C.teal),
              StatCard(widget.mine ? 'বিলের সংখ্যা' : 'নিট লাভ', widget.mine ? '${s['c']}' : money(n(s['profit'])), Icons.receipt_long, const Color(0xFF2E7D32)),
              StatCard('নতুন বাকি', money(n(s['due'])), Icons.schedule, C.red),
              StatCard('ডিসকাউন্ট', money(n(s['d'])), Icons.discount, const Color(0xFF6A1B9A)),
            ],
          ),
        _h('পেমেন্ট পদ্ধতি'),
        for (final m in methods) ListTile(dense: true, title: Text('${m['method']} (${m['c']} বিল)'), trailing: Text(money(n(m['t'])))),
        _h('সেরা বিক্রীত পণ্য'),
        for (final p in top) ListTile(dense: true, title: Text('${p['name']}'), subtitle: Text('পরিমাণ ${fmtQty(n(p['q']))}'), trailing: Text(money(n(p['r'])))),
        if (!widget.mine) ...[
          _h('কর্মী অনুযায়ী বিক্রি'),
          for (final u in users) ListTile(dense: true, title: Text('${u['name']} (${u['c']} বিল)'), trailing: Text(money(n(u['t'])))),
        ],
        _h('সাম্প্রতিক বিল'),
        for (final r in recent)
          ListTile(
            dense: true,
            title: Text('#${r['id']} • ${r['method']}${widget.mine ? '' : ' • ${r['uname']}'}'),
            subtitle: Text('${r['created_at']}'.replaceFirst('T', ' ')),
            trailing: Text(money(n(r['total'])), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
      ]);
}
