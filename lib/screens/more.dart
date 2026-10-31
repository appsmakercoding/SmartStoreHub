import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../core/db.dart';
import '../core/ui.dart';
import 'package:file_picker/file_picker.dart';
import '../core/license.dart';
import 'gate.dart';
import 'home.dart';
import 'reports.dart';
import 'suppliers.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final admin = Session.role == 'admin';
    return ListView(children: [
      _t(Icons.bar_chart, 'রিপোর্ট (লাভ-ক্ষতি, বিক্রি)', () => pushPage(context, 'রিপোর্ট', const ReportsScreen())),
      if (admin) _t(Icons.group_add, 'ইউজার ম্যানেজমেন্ট (ম্যানেজার/ক্যাশিয়ার)', () => pushPage(context, 'ইউজার ম্যানেজমেন্ট', const UsersScreen())),
      _t(Icons.local_shipping, 'সরবরাহকারী ও ক্রয় (মাল কেনা)', () => pushPage(context, 'সরবরাহকারী ও ক্রয়', const SuppliersScreen())),
      _t(Icons.history, 'অ্যাক্টিভিটি লগ', () => pushPage(context, 'অ্যাক্টিভিটি লগ', const LogScreen())),
      _t(Icons.person, 'প্রোফাইল ও পাসওয়ার্ড', () => pushPage(context, 'প্রোফাইল', const ProfileScreen())),
      if (admin)
        _t(Icons.backup, 'ডেটা ব্যাকআপ (শেয়ার/সংরক্ষণ)', () async {
          final path = pth.join(await getDatabasesPath(), 'smartstorehub.db');
          await Share.shareXFiles([XFile(path)], text: 'SmartStoreHub Backup');
          await Db.log('ব্যাকআপ নেওয়া হয়েছে');
        }),
      if (admin)
        _t(Icons.restore, 'ব্যাকআপ রিস্টোর', () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (dc) => AlertDialog(
              title: const Text('রিস্টোর করবেন?'),
              content: const Text('বর্তমান সব ডেটা ব্যাকআপ ফাইলের ডেটা দিয়ে বদলে যাবে। (পুরোনোটার একটি .bak কপি থাকবে)'),
              actions: [TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('না')), ElevatedButton(onPressed: () => Navigator.pop(dc, true), child: const Text('হ্যাঁ'))],
            ),
          );
          if (ok != true) return;
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
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
        }),
      if (admin)
        _t(Icons.verified, 'লাইসেন্স / সাবস্ক্রিপশন', () {
          final i = License.current ?? const LicenseInfo(LState.blocked, '', 0, '');
          Navigator.push(context, MaterialPageRoute(builder: (_) => LicenseScreen(info: i)));
        }),
      const SizedBox(height: 30),
      const Center(child: Text('SmartStoreHub v1.0 • Powered by Hasan', style: TextStyle(color: Colors.black45, fontSize: 12))),
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

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(backgroundColor: C.gold, onPressed: _add, child: const Icon(Icons.add)),
        body: ListView(children: [
          for (final u in list)
            ListTile(
              leading: CircleAvatar(child: Icon(u['role'] == 'admin' ? Icons.shield : u['role'] == 'manager' ? Icons.manage_accounts : Icons.point_of_sale)),
              title: Text('${u['name']} (${u['username']})'),
              subtitle: Text('${u['role']}'),
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
                for (final l in s.data!) ListTile(dense: true, title: Text('${l['action']}'), subtitle: Text('${l['uname']} • ${'${l['created_at']}'.replaceFirst('T', ' ')}')),
              ]),
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileScreen> {
  String shop = '';
  @override
  void initState() {
    super.initState();
    Db.setting('shop_name').then((v) { if (mounted) setState(() => shop = v); });
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
        if (Session.role == 'admin')
          ListTile(
            leading: const Icon(Icons.store),
            title: const Text('দোকানের নাম (রসিদে ছাপা হবে)'),
            subtitle: Text(shop),
            onTap: () async {
              final r = await askDialog(context, 'দোকানের নাম', ['নাম'], init: [shop]);
              if (r == null || r[0].isEmpty) return;
              await Db.setSetting('shop_name', r[0]);
              setState(() => shop = r[0]);
            },
          ),
      ]);
}
