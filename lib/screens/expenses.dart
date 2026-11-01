import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/ui.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpState();
}

class _ExpState extends State<ExpensesScreen> {
  int days = 1;
  List<Rec> list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = DateTime.now().subtract(Duration(days: days - 1));
    final r = await Db.expenses('${d.toIso8601String().substring(0, 10)}T00:00:00');
    if (mounted) setState(() => list = r);
  }

  Future<void> _add() async {
    String cat = 'ভাড়া';
    final amt = TextEditingController();
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sc) => StatefulBuilder(builder: (sc, set) {
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(sc).viewInsets.bottom + 18),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('নতুন খরচ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [for (final c in ['ভাড়া', 'বেতন', 'বিদ্যুৎ', 'পরিবহন', 'নাস্তা/চা', 'মেরামত', 'অন্যান্য']) ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => set(() => cat = c))]),
              const SizedBox(height: 10),
              TextField(controller: amt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'টাকার পরিমাণ (৳)')),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'নোট (ঐচ্ছিক)')),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if ((double.tryParse(amt.text) ?? 0) <= 0) {
                      snack(sc, 'টাকার পরিমাণ লিখুন');
                      return;
                    }
                    Navigator.pop(sc, true);
                  },
                  child: const Text('সংরক্ষণ'),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (ok != true) return;
    await Db.addExpense(cat, double.parse(amt.text), note.text.trim());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = list.fold<double>(0, (s, e) => s + n(e['amount']));
    return Scaffold(
      floatingActionButton: FloatingActionButton(backgroundColor: C.gold, onPressed: _add, child: const Icon(Icons.add)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: StatCard('মোট খরচ', money(total), Icons.receipt, const Color(0xFF6A1B9A))),
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
              ? const Center(child: Text('কোনো খরচ নেই', style: TextStyle(color: Colors.black45)))
              : ListView(children: [
                  for (final e in list)
                    ListTile(
                      title: Text('${e['category']} • ${money(n(e['amount']))}'),
                      subtitle: Text('${dt(e['created_at'])} • ${e['uname'] ?? ''}${'${e['note'] ?? ''}'.isEmpty ? '' : ' • ${e['note']}'}'),
                      trailing: Session.isAdmin
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline, color: C.red),
                              onPressed: () async {
                                if (!await confirmDialog(context, 'খরচ মুছবেন?', '${e['category']} ${money(n(e['amount']))}', yes: 'মুছুন')) return;
                                await Db.deleteExpense(e['id'] as int);
                                _load();
                              },
                            )
                          : null,
                    ),
                ]),
        ),
      ]),
    );
  }
}
