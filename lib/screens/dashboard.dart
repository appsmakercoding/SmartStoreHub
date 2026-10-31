import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/ui.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashState();
}

class _DashState extends State<DashboardScreen> {
  Rec s = {};
  double due = 0, stock = 0, supDue = 0;
  int low = 0;
  List<Rec> lowList = [], expList = [];
  List<MapEntry<String, double>> days = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final today = day(now);
    final from7 = day(now.subtract(const Duration(days: 6)));
    final sum = await Db.summary(today);
    final d7 = await Db.daily(from7);
    final map = {for (final r in d7) r['d'] as String: n(r['t'])};
    final ds = [for (var i = 6; i >= 0; i--) MapEntry(day(now.subtract(Duration(days: i))), 0.0)];
    final dd = [for (final e in ds) MapEntry(e.key, map[e.key] ?? 0.0)];
    final r = await Future.wait([Db.totalDue(), Db.stockValue(), Db.lowCount(), Db.lowStock(), Db.expiring(), Db.supplierDue()]);
    if (!mounted) return;
    setState(() {
      s = sum;
      days = dd;
      due = r[0] as double;
      stock = r[1] as double;
      low = r[2] as int;
      lowList = r[3] as List<Rec>;
      expList = r[4] as List<Rec>;
      supDue = r[5] as double;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (s.isEmpty) return const Center(child: CircularProgressIndicator());
    final mx = days.fold<double>(1, (m, e) => e.value > m ? e.value : m);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (Session.role == 'admin')
          const Card(color: Color(0xFFFFF4D6), child: ListTile(leading: Icon(Icons.info, color: C.gold), title: Text('নিরাপত্তার জন্য ডিফল্ট পাসওয়ার্ড (admin123) আরও > প্রোফাইল থেকে বদলে নিন', style: TextStyle(fontSize: 12)))),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.7,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            StatCard('আজকের বিক্রি', money(n(s['t'])), Icons.trending_up, C.teal),
            StatCard('আজকের লাভ', money(n(s['profit'])), Icons.savings, const Color(0xFF2E7D32)),
            StatCard('মোট বাকি', money(due), Icons.account_balance_wallet, C.red),
            StatCard('স্টকের মূল্য', money(stock), Icons.warehouse, const Color(0xFF1565C0)),
            StatCard('সরবরাহকারীর পাওনা', money(supDue), Icons.local_shipping, const Color(0xFFEF6C00)),
            StatCard('স্টক কম', '$low টি', Icons.warning_amber, C.red),
          ],
        ),
        const SizedBox(height: 14),
        const Text('গত ৭ দিনের বিক্রি', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            height: 170,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final e in days)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(e.value == 0 ? '' : e.value.toStringAsFixed(0), style: const TextStyle(fontSize: 9)),
                    Container(height: 90 * e.value / mx + 2, margin: const EdgeInsets.symmetric(horizontal: 5), decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 4),
                    Text(e.key.substring(8), style: const TextStyle(fontSize: 10)),
                  ]),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Text('⚠ স্টক কম ($low টি)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        for (final p in lowList) ListTile(dense: true, title: Text('${p['name']}'), trailing: Text('${fmtQty(n(p['stock']))}', style: const TextStyle(color: C.red, fontWeight: FontWeight.bold))),
        if (lowList.isEmpty) const Text('সব ঠিক আছে ✔', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 10),
        const Text('⏳ মেয়াদ শেষ হচ্ছে (৩০ দিনের মধ্যে)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        for (final p in expList) ListTile(dense: true, title: Text('${p['name']}'), trailing: Text('${p['expiry']}', style: const TextStyle(color: C.red))),
        if (expList.isEmpty) const Text('কোনো সতর্কতা নেই ✔', style: TextStyle(color: Colors.black54)),
      ]),
    );
  }
}
