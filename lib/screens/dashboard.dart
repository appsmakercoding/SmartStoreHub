import 'package:flutter/material.dart';
import '../core/backup.dart';
import '../core/db.dart';
import '../core/ui.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashState();
}

class _DashState extends State<DashboardScreen> {
  Rec p = {};
  double due = 0, supDue = 0;
  int dueCount = 0;
  Rec stats = {};
  List<Rec> lowList = [], expList = [];
  List<MapEntry<String, double>> days = [];
  bool needBackup = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final today = '${day(now)}T00:00:00';
    final from7 = '${day(now.subtract(const Duration(days: 6)))}T00:00:00';
    final pnl = await Db.pnl(today);
    final d7 = await Db.daily(from7);
    final map = {for (final r in d7) r['d'] as String: n(r['t'])};
    final dd = [for (var i = 6; i >= 0; i--) MapEntry(day(now.subtract(Duration(days: i))), map[day(now.subtract(Duration(days: i)))] ?? 0.0)];
    final cd = await Db.totalDue();
    final dc = await Db.dueCount();
    final sd = await Db.supplierDue();
    final st = await Db.productStats();
    final low = await Db.lowStock();
    final exp = await Db.expiring();
    final lb = DateTime.tryParse(await Db.setting('last_backup'));
    if (!mounted) return;
    setState(() {
      p = pnl;
      days = dd;
      due = cd;
      dueCount = dc;
      supDue = sd;
      stats = st;
      lowList = low;
      expList = exp;
      needBackup = Session.isAdmin && (lb == null || now.difference(lb).inDays >= 7);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (p.isEmpty) return const Center(child: CircularProgressIndicator());
    final mx = days.fold<double>(1, (m, e) => e.value > m ? e.value : m);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (Session.isAdmin)
          const Card(color: Color(0xFFFFF4D6), child: ListTile(leading: Icon(Icons.info, color: C.gold), title: Text('নিরাপত্তার জন্য ডিফল্ট পাসওয়ার্ড (admin123) আরও > প্রোফাইল থেকে বদলে নিন', style: TextStyle(fontSize: 12, color: Colors.black87)))),
        if (needBackup)
          Card(
            color: const Color(0xFFFFE5E5),
            child: ListTile(
              leading: const Icon(Icons.backup, color: C.red),
              title: const Text('ডেটা ব্যাকআপ নেওয়া হয়নি (৭ দিনের বেশি)', style: TextStyle(fontSize: 13, color: Colors.black87)),
              trailing: TextButton(onPressed: () async { await doBackup(); _load(); }, child: const Text('এখনই নিন')),
            ),
          ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.7,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            StatCard('আজকের বিক্রি', money(n(p['sales'])), Icons.trending_up, C.teal),
            StatCard('আজকের নিট লাভ', money(n(p['net'])), Icons.savings, const Color(0xFF2E7D32)),
            StatCard('আজ বাকি আদায়', money(n(p['collected'])), Icons.payments, const Color(0xFF00838F)),
            StatCard('আজকের খরচ', money(n(p['expenses'])), Icons.receipt, const Color(0xFF6A1B9A)),
            StatCard('গ্রাহকের বাকি ($dueCount জন)', money(due), Icons.account_balance_wallet, C.red),
            StatCard('সরবরাহকারীর পাওনা', money(supDue), Icons.local_shipping, const Color(0xFFEF6C00)),
            StatCard('স্টকের মূল্য', money(n(stats['v'])), Icons.warehouse, const Color(0xFF1565C0)),
            StatCard('স্টক কম', '${stats['low']} টি', Icons.warning_amber, C.red),
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
        const Text('⚠ স্টক কম', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        for (final x in lowList) ListTile(dense: true, title: Text('${x['name']}'), trailing: Text('${fmtQty(n(x['stock']))} ${x['unit'] ?? ''}', style: const TextStyle(color: C.red, fontWeight: FontWeight.bold))),
        if (lowList.isEmpty) const Text('সব ঠিক আছে ✔', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 10),
        const Text('⏳ মেয়াদ শেষ হচ্ছে (৩০ দিনের মধ্যে)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        for (final x in expList) ListTile(dense: true, title: Text('${x['name']}'), trailing: Text('${x['expiry']}', style: const TextStyle(color: C.red))),
        if (expList.isEmpty) const Text('কোনো সতর্কতা নেই ✔', style: TextStyle(color: Colors.black54)),
      ]),
    );
  }
}
