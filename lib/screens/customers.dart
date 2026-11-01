import 'package:flutter/material.dart';
import '../core/contact.dart';
import '../core/db.dart';
import '../core/ui.dart';
import '../core/voucher.dart';
import 'sales.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustState();
}

class _CustState extends State<CustomersScreen> {
  List<Rec> list = [];
  bool dueOnly = false;
  final q = TextEditingController();
  double totalDue = 0;
  int dueCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.customers(s: q.text, dueOnly: dueOnly);
    final t = await Db.totalDue();
    final c = await Db.dueCount();
    if (mounted) {
      setState(() {
        list = r;
        totalDue = t;
        dueCount = c;
      });
    }
  }

  Future<void> _add() async {
    final r = await askDialog(context, 'নতুন গ্রাহক', ['নাম', 'মোবাইল নম্বর', 'বাকির সীমা ৳ (০ = সীমাহীন)'], init: ['', '', '0'], numeric: {1, 2});
    if (r == null || r[0].isEmpty) return;
    if (r[1].isEmpty) {
      snack(context, 'মোবাইল নম্বর দিন');
      return;
    }
    await Db.addCustomer(r[0], r[1], limit: double.tryParse(r[2]) ?? 0);
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(backgroundColor: C.gold, onPressed: _add, child: const Icon(Icons.person_add)),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Row(children: [
              Expanded(child: StatCard('মোট বাকি (পাবো)', money(totalDue), Icons.account_balance_wallet, C.red)),
              const SizedBox(width: 8),
              Expanded(child: StatCard('বাকি গ্রাহক', '$dueCount জন', Icons.people, const Color(0xFFEF6C00))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(controller: q, onChanged: (_) => _load(), decoration: const InputDecoration(hintText: 'নাম / মোবাইল খুঁজুন', prefixIcon: Icon(Icons.search), isDense: true)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              ChoiceChip(label: const Text('সব গ্রাহক'), selected: !dueOnly, onSelected: (_) { dueOnly = false; _load(); }),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('বাকি তালিকা'), selected: dueOnly, onSelected: (_) { dueOnly = true; _load(); }),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('কোনো গ্রাহক নেই', style: TextStyle(color: Colors.black45)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final x = list[i];
                      final due = n(x['due']);
                      return ListTile(
                        leading: CircleAvatar(child: Text('${x['name']}'.characters.first)),
                        title: Text('${x['name']}'),
                        subtitle: Text('${x['phone'] ?? ''}'),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(money(due), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: due > 0 ? C.red : C.teal)),
                          Text(due > 0 ? 'বাকি' : 'পরিষ্কার', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ]),
                        onTap: () async {
                          await go(context, CustomerDetailScreen(customerId: x['id'] as int));
                          _load();
                        },
                      );
                    },
                  ),
          ),
        ]),
      );
}

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;
  const CustomerDetailScreen({super.key, required this.customerId});
  @override
  State<CustomerDetailScreen> createState() => _CustDetState();
}

class _CustDetState extends State<CustomerDetailScreen> {
  Rec? c;
  List<Rec> ledger = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.customer(widget.customerId);
    final l = await Db.customerLedger(widget.customerId);
    if (mounted) {
      setState(() {
        c = r;
        ledger = l.reversed.toList();
      });
    }
  }

  Future<String> _reminder() async {
    final shop = await Db.setting('shop_name', 'আমাদের দোকান');
    return 'সম্মানিত ${c!['name']}, $shop-এ আপনার মোট বকেয়া ${money(n(c!['due']))}। অনুগ্রহ করে দ্রুত পরিশোধ করুন। ধন্যবাদ।';
  }

  Future<void> _notify(String how) async {
    final phone = '${c!['phone'] ?? ''}';
    if (phone.isEmpty) {
      snack(context, 'এই গ্রাহকের মোবাইল নম্বর নেই');
      return;
    }
    final msg = await _reminder();
    final ok = how == 'wa' ? await whatsappTo(phone, msg) : how == 'sms' ? await smsTo(phone, msg) : await callPhone(phone);
    if (!ok && mounted) snack(context, 'অ্যাপ খোলা যায়নি');
  }

  Future<void> _collect() async {
    final due = n(c!['due']);
    final r = await askDialog(context, 'বকেয়া আদায় • ${money(due)}', ['আদায়ের পরিমাণ (৳)'], init: [due.toStringAsFixed(0)], numeric: {0});
    final v = r == null ? null : double.tryParse(r[0]);
    if (v == null || v <= 0) return;
    if (v > due + 0.001) {
      if (mounted) snack(context, 'বাকির চেয়ে বেশি আদায় করা যাবে না');
      return;
    }
    await Db.receive(widget.customerId, v);
    final text = await collectionVoucher(c!, v, due);
    await _load();
    if (mounted) showVoucher(context, 'আদায় সম্পন্ন ✔', text, phone: '${c!['phone'] ?? ''}');
  }

  Future<void> _statement() async {
    final b = StringBuffer('${c!['name']} এর হিসাব\n');
    for (final e in ledger.reversed) {
      final t = '${e['type']}';
      final label = t == 'sale' ? 'বিল #${e['sale_id']}' : t == 'cash' ? 'আদায়' : t == 'return' ? 'রিটার্ন সমন্বয়' : 'বিল বাতিল';
      b.writeln('${dt(e['date'])}  $label  ${money(n(e['effect']))}  (বাকি ${money(n(e['bal']))})');
    }
    b.writeln('মোট বকেয়া: ${money(n(c!['due']))}');
    await showVoucher(context, 'খতিয়ান', b.toString(), phone: '${c!['phone'] ?? ''}');
  }

  @override
  Widget build(BuildContext context) {
    if (c == null) return Scaffold(appBar: AppBar(title: const Text('গ্রাহক')), body: const Center(child: CircularProgressIndicator()));
    final due = n(c!['due']);
    final limit = n(c!['credit_limit']);
    return Scaffold(
      appBar: AppBar(title: Text('${c!['name']}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        StatCard('${c!['phone'] ?? ''}  •  বর্তমান বাকি', money(due), Icons.account_balance_wallet, due > 0 ? C.red : C.teal),
        if (limit > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('বাকির সীমা: ${money(limit)}', style: const TextStyle(color: Colors.black54))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (due > 0) ElevatedButton.icon(onPressed: _collect, icon: const Icon(Icons.payments), label: const Text('আদায়')),
          if (due > 0) OutlinedButton.icon(onPressed: () => _notify('wa'), icon: const Icon(Icons.chat), label: const Text('WhatsApp')),
          if (due > 0) OutlinedButton.icon(onPressed: () => _notify('sms'), icon: const Icon(Icons.sms), label: const Text('SMS')),
          OutlinedButton.icon(onPressed: () => _notify('call'), icon: const Icon(Icons.call), label: const Text('কল')),
          OutlinedButton.icon(onPressed: _statement, icon: const Icon(Icons.receipt_long), label: const Text('খতিয়ান শেয়ার')),
        ]),
        sectionTitle('খতিয়ান (বিল ও আদায়)'),
        if (ledger.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('কোনো লেনদেন নেই', style: TextStyle(color: Colors.black45))),
        for (final e in ledger) _entry(e),
      ]),
    );
  }

  Widget _entry(Rec e) {
    final t = '${e['type']}';
    final eff = n(e['effect']);
    String title;
    String sub = dt(e['date']);
    if (t == 'sale') {
      title = 'বিল #${e['sale_id']} • মোট ${money(n(e['total']))}';
      sub += ' • পরিশোধ ${money(n(e['paid']))}';
      if (e['status'] == 'cancelled') title += ' (বাতিল)';
    } else if (t == 'cash') {
      title = 'বকেয়া আদায়';
    } else if (t == 'return') {
      title = 'রিটার্ন সমন্বয় (বিল #${e['sale_id']})';
    } else {
      title = 'বিল বাতিল (বিল #${e['sale_id']})';
    }
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(sub),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(eff == 0 ? '—' : '${eff > 0 ? '+' : '−'}${money(eff.abs())}', style: TextStyle(fontWeight: FontWeight.bold, color: eff > 0 ? C.red : C.teal)),
        Text('বাকি ${money(n(e['bal']))}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ]),
      onTap: t == 'sale' ? () => go(context, SaleDetailScreen(saleId: e['sale_id'] as int)) : null,
    );
  }
}
