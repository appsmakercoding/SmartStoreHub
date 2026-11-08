import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/backup.dart';
import '../core/db.dart';
import '../core/export.dart';
import '../core/pdf_reports.dart';
import '../core/license.dart';
import '../core/ui.dart';
import 'cashclose.dart';
import 'expenses.dart';
import 'gate.dart';
import 'home.dart';
import 'reports.dart';
import 'sales.dart';
import 'suppliers.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final admin = Session.isAdmin;
    return ListView(children: [
      sectionTitle('হিসাব-নিকাশ'),
      _t(Icons.bar_chart, 'রিপোর্ট (লাভ-ক্ষতি, বিক্রি, বাকি)', () => pushPage(context, 'রিপোর্ট', const ReportsScreen())),
      _t(Icons.list_alt, 'বিল তালিকা (রিটার্ন/বাতিল)', () => pushPage(context, 'বিল তালিকা', const SalesScreen())),
      _t(Icons.local_shipping, 'সরবরাহকারী ও ক্রয় (মাল কেনা)', () => pushPage(context, 'সরবরাহকারী ও ক্রয়', const SuppliersScreen())),
      _t(Icons.receipt, 'দোকানের খরচ', () => pushPage(context, 'দোকানের খরচ', const ExpensesScreen())),
      _t(Icons.account_balance, 'দৈনিক ক্যাশ ক্লোজিং', () => pushPage(context, 'দৈনিক ক্যাশ ক্লোজিং', const CashCloseScreen())),
      if (!Session.isCashier)
        _t(Icons.picture_as_pdf, 'PDF রিপোর্ট (শেয়ার/প্রিন্ট)', () async {
          final k = await showDialog<String>(
            context: context,
            builder: (dc) => SimpleDialog(title: const Text('কোন PDF চান?'), children: [
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'b1'), child: const Text('ব্যবসায়িক রিপোর্ট • আজ')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'b7'), child: const Text('ব্যবসায়িক রিপোর্ট • ৭ দিন')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'b30'), child: const Text('ব্যবসায়িক রিপোর্ট • ৩০ দিন')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'dues'), child: const Text('গ্রাহকের বাকি তালিকা')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'sup'), child: const Text('সরবরাহকারীর হিসাব')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'stock'), child: const Text('স্টক তালিকা')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'exp'), child: const Text('খরচ (৩০ দিন)')),
            ]),
          );
          if (k == null || !context.mounted) return;
          await runPdf(context, () async {
            if (k == 'b1') await pdfBusinessReport(1);
            if (k == 'b7') await pdfBusinessReport(7);
            if (k == 'b30') await pdfBusinessReport(30);
            if (k == 'dues') await pdfCustomerDues();
            if (k == 'sup') await pdfSupplierList();
            if (k == 'stock') await pdfStockList();
            if (k == 'exp') await pdfExpenses();
          });
        }),
      if (!Session.isCashier)
        _t(Icons.table_chart, 'এক্সেল/CSV এক্সপোর্ট (হিসাবরক্ষকের জন্য)', () async {
          final k = await showDialog<String>(
            context: context,
            builder: (dc) => SimpleDialog(title: const Text('কী এক্সপোর্ট করবেন?'), children: [
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'sales'), child: const Text('বিক্রি (গত ৩০ দিন)')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'dues'), child: const Text('গ্রাহকের বাকি তালিকা')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'products'), child: const Text('পণ্য ও স্টক তালিকা')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'suppliers'), child: const Text('সরবরাহকারীর হিসাব')),
              SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'expenses'), child: const Text('খরচ (গত ৩০ দিন)')),
            ]),
          );
          if (k != null) await exportCsv(k);
        }),
      sectionTitle('সেটিংস ও সুরক্ষা'),
      if (admin) _t(Icons.group_add, 'ইউজার ম্যানেজমেন্ট (ম্যানেজার/ক্যাশিয়ার)', () => pushPage(context, 'ইউজার ম্যানেজমেন্ট', const UsersScreen())),
      _t(Icons.history, 'অ্যাক্টিভিটি লগ (কে কী করল)', () => pushPage(context, 'অ্যাক্টিভিটি লগ', const LogScreen())),
      _t(Icons.person, 'প্রোফাইল ও সেটিংস', () => pushPage(context, 'প্রোফাইল ও সেটিংস', const ProfileScreen())),
      if (admin) sectionTitle('ডেটা ও লাইসেন্স'),
      if (admin) _t(Icons.backup, 'ডেটা ব্যাকআপ (শেয়ার/সংরক্ষণ)', () => doBackup()),
      if (admin)
        _t(Icons.restore, 'ব্যাকআপ রিস্টোর', () async {
          final ok = await confirmDialog(context, 'রিস্টোর করবেন?', 'বর্তমান সব ডেটা ব্যাকআপ ফাইলের ডেটা দিয়ে বদলে যাবে। (পুরোনোটার একটি .bak কপি থাকবে)');
          if (!ok) return;
          final r = await FilePicker.platform.pickFiles();
          final path = r?.files.single.path;
          if (path == null) return;
          final done = await Db.restore(path);
          if (!context.mounted) return;
          if (!done) {
            snack(context, 'এটি সঠিক ব্যাকআপ ফাইল নয়');
            return;
          }
          Session.user = null;
          snack(context, 'রিস্টোর সম্পন্ন, আবার লগইন করুন');
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
        }),
      if (admin)
        _t(Icons.verified, 'লাইসেন্স / সাবস্ক্রিপশন', () {
          final i = License.current ?? const LicenseInfo(LState.blocked, '', 0, '');
          Navigator.push(context, MaterialPageRoute(builder: (_) => LicenseScreen(info: i)));
        }),
      const SizedBox(height: 30),
      const Center(child: Text('SmartStoreHub v2.0 • Powered by Hasan', style: TextStyle(color: Colors.black45, fontSize: 12))),
      const SizedBox(height: 20),
    ]);
  }

  Widget _t(IconData i, String t, VoidCallback f) => ListTile(leading: Icon(i, color: C.teal), title: Text(t), trailing: const Icon(Icons.chevron_right), onTap: f);
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersState();
}

class _UsersState extends State<UsersScreen> {
  List<Rec> list = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.users();
    if (mounted) setState(() => list = r);
  }

  Future<void> _add() async {
    final role = await showDialog<String>(
      context: context,
      builder: (dc) => SimpleDialog(title: const Text('ভূমিকা নির্বাচন'), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'manager'), child: const Text('ম্যানেজার')),
        SimpleDialogOption(onPressed: () => Navigator.pop(dc, 'cashier'), child: const Text('ক্যাশিয়ার')),
      ]),
    );
    if (role == null || !mounted) return;
    final r = await askDialog(context, 'নতুন ইউজার', ['নাম', 'ইউজারনেম', 'পাসওয়ার্ড / PIN'], secret: {2});
    if (r == null || r.any((e) => e.isEmpty)) return;
    if (list.where((u) => u['active'] == 1).length >= License.maxUsers) {
      if (mounted) snack(context, 'আপনার প্ল্যানে সর্বোচ্চ ${License.maxUsers} জন ইউজার। প্ল্যান আপগ্রেড করুন।');
      return;
    }
    final err = await Db.addUser(r[0], r[1], r[2], role);
    if (err != null && mounted) snack(context, err);
    _load();
  }

  Future<void> _delete(Rec u) async {
    final ok = await confirmDialog(context, 'ইউজার মুছবেন?', '${u['name']} (${u['username']}) মুছে যাবে। তার আগের সব বিক্রির হিসাব অক্ষত থাকবে।', yes: 'মুছুন');
    if (!ok) return;
    final err = await Db.deleteUser(u['id'] as int);
    if (err != null && mounted) snack(context, err);
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(backgroundColor: C.gold, onPressed: _add, child: const Icon(Icons.add)),
        body: ListView(children: [
          for (final u in list)
            ListTile(
              leading: CircleAvatar(child: Icon(u['role'] == 'admin' ? Icons.shield : u['role'] == 'manager' ? Icons.manage_accounts : Icons.point_of_sale)),
              title: Text('${u['name']} (${u['username']})'),
              subtitle: Text(u['role'] == 'admin' ? 'এডমিন' : u['role'] == 'manager' ? 'ম্যানেজার' : 'ক্যাশিয়ার'),
              trailing: u['role'] == 'admin'
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.key),
                        tooltip: 'পাসওয়ার্ড রিসেট',
                        onPressed: () async {
                          final r = await askDialog(context, 'নতুন পাসওয়ার্ড', ['নতুন পাসওয়ার্ড'], secret: {0});
                          if (r == null || r[0].isEmpty) return;
                          await Db.resetPw(u['id'] as int, '${u['username']}', r[0]);
                          if (mounted) snack(context, 'পাসওয়ার্ড পরিবর্তন হয়েছে');
                        },
                      ),
                      Switch(value: u['active'] == 1, onChanged: (v) async { await Db.setActive(u['id'] as int, v); _load(); }),
                      IconButton(icon: const Icon(Icons.delete_outline, color: C.red), tooltip: 'মুছুন', onPressed: () => _delete(u)),
                    ]),
            ),
        ]),
      );
}

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Rec>>(
        future: Db.logs(),
        builder: (c, s) => !s.hasData
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                for (final l in s.data!) ListTile(dense: true, title: Text('${l['action']}'), subtitle: Text('${l['uname']} • ${dt(l['created_at'])}')),
              ]),
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileScreen> {
  String shop = '', phone = '', addr = '', vat = '0', maxDisc = '10';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await Db.setting('shop_name');
    final b = await Db.setting('shop_phone');
    final c = await Db.setting('shop_address');
    final d = await Db.setting('vat_pct', '0');
    final e = await Db.setting('max_disc_pct', '10');
    if (mounted) {
      setState(() {
        shop = a;
        phone = b;
        addr = c;
        vat = d;
        maxDisc = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(leading: const Icon(Icons.person), title: Text(Session.name), subtitle: Text('${Session.username} • ${Session.role}')),
        ListTile(
          leading: const Icon(Icons.lock_reset),
          title: const Text('পাসওয়ার্ড পরিবর্তন'),
          onTap: () async {
            final r = await askDialog(context, 'পাসওয়ার্ড পরিবর্তন', ['বর্তমান পাসওয়ার্ড', 'নতুন পাসওয়ার্ড'], secret: {0, 1});
            if (r == null || r[1].length < 4) {
              if (r != null && mounted) snack(context, 'নতুন পাসওয়ার্ড কমপক্ষে ৪ অক্ষর');
              return;
            }
            final ok = await Db.changePw(r[0], r[1]);
            if (mounted) snack(context, ok ? 'পাসওয়ার্ড বদলানো হয়েছে ✔' : 'বর্তমান পাসওয়ার্ড ভুল');
          },
        ),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (c, m, _) => SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('ডার্ক মোড'),
            value: m == ThemeMode.dark,
            onChanged: (v) async {
              themeMode.value = v ? ThemeMode.dark : ThemeMode.light;
              await Db.setSetting('dark', v ? '1' : '0');
            },
          ),
        ),
        if (Session.isAdmin)
          ListTile(
            leading: const Icon(Icons.store),
            title: const Text('দোকানের তথ্য ও সেটিংস'),
            subtitle: Text('$shop • ভ্যাট $vat% • ক্যাশিয়ার ডিসকাউন্ট সীমা $maxDisc%'),
            onTap: () async {
              final r = await askDialog(
                context,
                'দোকানের তথ্য ও সেটিংস',
                ['দোকানের নাম (ভাউচারে ছাপা হবে)', 'দোকানের ফোন', 'ঠিকানা', 'ভ্যাট % (০ = নেই)', 'ক্যাশিয়ারের সর্বোচ্চ ডিসকাউন্ট %'],
                init: [shop, phone, addr, vat, maxDisc],
                numeric: {3, 4},
              );
              if (r == null || r[0].isEmpty) return;
              await Db.setSetting('shop_name', r[0]);
              await Db.setSetting('shop_phone', r[1]);
              await Db.setSetting('shop_address', r[2]);
              await Db.setSetting('vat_pct', '${double.tryParse(r[3]) ?? 0}');
              await Db.setSetting('max_disc_pct', '${double.tryParse(r[4]) ?? 10}');
              await Db.log('দোকানের সেটিংস বদলানো হয়েছে');
              _load();
            },
          ),
        if (Session.isAdmin)
          ListTile(
            leading: const Icon(Icons.science, color: C.gold),
            title: const Text('ডেমো ডেটা যোগ করুন'),
            subtitle: const Text('নতুন ক্রেতাকে অ্যাপ দেখানোর জন্য নমুনা পণ্য, গ্রাহক ও বিক্রি'),
            onTap: () async {
              if (!await confirmDialog(context, 'ডেমো ডেটা যোগ করবেন?', 'নমুনা পণ্য, গ্রাহক ও কয়েকটি বিক্রি যোগ হবে। আসল ব্যবহারের আগে "নতুন শুরু" দিয়ে মুছে ফেলবেন।')) return;
              await Db.loadDemo();
              if (mounted) snack(context, 'ডেমো ডেটা যোগ হয়েছে ✔');
            },
          ),
        if (Session.isAdmin)
          ListTile(
            leading: const Icon(Icons.delete_forever, color: C.red),
            title: const Text('সব ডেটা মুছে নতুন শুরু', style: TextStyle(color: C.red)),
            subtitle: const Text('পণ্য, গ্রাহক, বিক্রি, হিসাব সব মুছবে (ইউজার ও সেটিংস থাকবে)'),
            onTap: () async {
              if (!await confirmDialog(context, 'সব ডেটা মুছবেন?', 'পণ্য, গ্রাহক, বিক্রি, সরবরাহকারী ও সব হিসাব স্থায়ীভাবে মুছে যাবে। আগে ব্যাকআপ নিয়েছেন তো?', yes: 'হ্যাঁ, মুছুন')) return;
              if (!mounted) return;
              if (!await confirmDialog(context, 'শেষবার নিশ্চিত করুন', 'এটি ফেরত আনা যাবে না।', yes: 'মুছে ফেলুন')) return;
              await Db.resetData();
              if (mounted) snack(context, 'নতুন শুরুর জন্য প্রস্তুত ✔');
            },
          ),
      ]);
}
