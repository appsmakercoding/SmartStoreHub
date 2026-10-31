import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/db.dart';
import '../core/ui.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustState();
}

class _CustState extends State<CustomersScreen> {
  List<Rec> list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.customers();
    if (mounted) setState(() => list = r);
  }

  Future<void> _add() async {
    final r = await askDialog(context, 'নতুন গ্রাহক', ['নাম', 'মোবাইল']);
    if (r == null || r[0].isEmpty) return;
    await Db.addCustomer(r[0], r[1]);
    _load();
  }

  Future<void> _collect(Rec c) async {
    final r = await askDialog(context, '${c['name']} • বকেয়া ${money(n(c['due']))}', ['আদায়ের পরিমাণ (৳)'], numeric: {0});
    final v = r == null ? null : double.tryParse(r[0]);
    if (v == null || v <= 0) return;
    await Db.receive(c['id'] as int, v);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = list.fold<double>(0, (s, c) => s + n(c['due']));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(backgroundColor: C.gold, onPressed: _add, child: const Icon(Icons.person_add)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: StatCard('মোট বাকি-বকেয়া (পাবো)', money(total), Icons.account_balance_wallet, C.red)),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final x = list[i];
              final due = n(x['due']);
              return ListTile(
                leading: CircleAvatar(child: Text('${x['name']}'.characters.first)),
                title: Text('${x['name']}'),
                subtitle: Text('${x['phone'] ?? ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(money(due), style: TextStyle(fontWeight: FontWeight.bold, color: due > 0 ? C.red : C.teal)),
                  if (due > 0)
                    IconButton(
                      icon: const Icon(Icons.share, size: 20),
                      tooltip: 'রিমাইন্ডার',
                      onPressed: () => Share.share('প্রিয় ${x['name']}, আপনার বকেয়া ${money(due)}। অনুগ্রহ করে পরিশোধ করুন। ধন্যবাদ।'),
                    ),
                ]),
                onTap: due > 0 ? () => _collect(x) : null,
              );
            },
          ),
        ),
      ]),
    );
  }
}
