import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/logo.dart';
import '../core/ui.dart';
import 'shell.dart';

class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  late final u = TextEditingController(text: widget.role == 'admin' ? 'admin' : '');
  final p = TextEditingController();
  bool busy = false, hide = true;
  String? err;

  static const titles = {'admin': 'এডমিন লগইন', 'manager': 'ম্যানেজার লগইন', 'cashier': 'ক্যাশিয়ার লগইন'};

  Future<void> _go() async {
    setState(() { busy = true; err = null; });
    final user = await Db.login(u.text.trim(), p.text, widget.role);
    if (!mounted) return;
    if (user == null) {
      setState(() { busy = false; err = 'ইউজারনেম বা পাসওয়ার্ড ভুল'; });
      return;
    }
    Session.user = user;
    await Db.log('লগইন');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(titles[widget.role]!)),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const AppLogo(size: 80),
              const SizedBox(height: 24),
              TextField(controller: u, decoration: const InputDecoration(labelText: 'ইউজারনেম', prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 14),
              TextField(
                controller: p,
                obscureText: hide,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  labelText: widget.role == 'cashier' ? 'পাসওয়ার্ড / PIN' : 'পাসওয়ার্ড',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)),
                ),
              ),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: C.red))),
              const SizedBox(height: 22),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: busy ? null : _go, child: busy ? const CircularProgressIndicator() : const Text('লগইন'))),
              if (widget.role == 'admin') const Padding(padding: EdgeInsets.only(top: 14), child: Text('প্রথমবার: admin / admin123 (লগইনের পর অবশ্যই পরিবর্তন করুন)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54))),
            ]),
          ),
        ),
      );
}
