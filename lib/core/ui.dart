import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class C {
  static const teal = Color(0xFF0B6E4F);
  static const dark = Color(0xFF053B2C);
  static const gold = Color(0xFFF2B632);
  static const bg = Color(0xFFF4F7F6);
  static const red = Color(0xFFD64545);
}

final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

ThemeData appTheme([Brightness b = Brightness.light]) {
  final dark = b == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.teal, secondary: C.gold, brightness: b),
    scaffoldBackgroundColor: dark ? const Color(0xFF0F1513) : C.bg,
    appBarTheme: const AppBarTheme(backgroundColor: C.dark, foregroundColor: Colors.white),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1B2421) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: C.teal,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

String money(num v) => '৳${NumberFormat('#,##0.##').format(v)}';
double n(Object? v) => (v as num?)?.toDouble() ?? 0;
String nowIso() => DateTime.now().toIso8601String().substring(0, 19);
String fmtQty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
void pushPage(BuildContext c, String t, Widget w) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(t)), body: w)));

String genBarcode() {
  final r = Random();
  var s = '20';
  for (var i = 0; i < 10; i++) {
    s += '${r.nextInt(10)}';
  }
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(s[i]) * (i.isEven ? 1 : 3);
  }
  return '$s${(10 - sum % 10) % 10}';
}

Future<List<String>?> askDialog(BuildContext c, String title, List<String> labels,
    {List<String>? init, Set<int> numeric = const {}, Set<int> secret = const {}, Set<int> scanFields = const {}, Future<String?> Function()? scan}) {
  final ctl = [
    for (var i = 0; i < labels.length; i++)
      TextEditingController(text: init != null && i < init.length ? init[i] : '')
  ];
  return showDialog<List<String>>(
    context: c,
    builder: (dc) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: ctl[i],
                obscureText: secret.contains(i),
                keyboardType: numeric.contains(i)
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: labels[i],
                  suffixIcon: scanFields.contains(i) && scan != null
                      ? IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'ক্যামেরায় স্ক্যান',
                          onPressed: () async {
                            final v = await scan();
                            if (v != null) ctl[i].text = v;
                          },
                        )
                      : null,
                ),
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dc), child: const Text('বাতিল')),
        ElevatedButton(
            onPressed: () => Navigator.pop(dc, [for (final x in ctl) x.text.trim()]),
            child: const Text('সংরক্ষণ')),
      ],
    ),
  );
}

class StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const StatCard(this.label, this.value, this.icon, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Row(children: [
          CircleAvatar(backgroundColor: color.withAlpha(30), child: Icon(icon, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              FittedBox(child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ]),
          ),
        ]),
      );
}

Future<bool> confirmDialog(BuildContext c, String title, String msg, {String yes = 'হ্যাঁ'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (dc) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('না')),
        ElevatedButton(onPressed: () => Navigator.pop(dc, true), child: Text(yes)),
      ],
    ),
  );
  return r == true;
}

String dt(Object? v) {
  final s = '$v'.replaceFirst('T', ' ');
  return s.length >= 16 ? s.substring(0, 16) : s;
}

Future<T?> go<T>(BuildContext c, Widget w) => Navigator.push<T>(c, MaterialPageRoute(builder: (_) => w));

Widget sectionTitle(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: C.teal)),
    );

/// অ্যাপের যেকোনো জায়গায় স্পর্শ করলে অটো-লগআউট টাইমার রিসেট হয়
class Activity {
  static VoidCallback? onTouch;
}

/// PDF তৈরির সময় বার্তা দেখায় এবং ত্রুটি ধরে
Future<void> runPdf(BuildContext c, Future<void> Function() f) async {
  snack(c, 'PDF তৈরি হচ্ছে…');
  try {
    await f();
  } catch (e) {
    if (c.mounted) snack(c, 'PDF তৈরি করা যায়নি: $e');
  }
}
