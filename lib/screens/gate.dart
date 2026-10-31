import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/license.dart';
import '../core/logo.dart';
import '../core/ui.dart';
import 'home.dart';

/// অ্যাপ চালুর সময় লাইসেন্স যাচাই করে: ঠিক থাকলে Home, নয়তো অ্যাক্টিভেশন স্ক্রিন
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  LicenseInfo? info;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (mounted) setState(() => info = null);
    final i = await License.check();
    License.current = i;
    if (mounted) setState(() => info = i);
  }

  @override
  Widget build(BuildContext context) {
    if (info == null) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [C.dark, C.teal], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [AppLogo(size: 100), SizedBox(height: 24), CircularProgressIndicator(color: C.gold)])),
        ),
      );
    }
    return info!.ok ? const HomeScreen() : LicenseScreen(info: info!, onDone: _run);
  }
}

class LicenseScreen extends StatefulWidget {
  final LicenseInfo info;
  final VoidCallback? onDone;
  const LicenseScreen({super.key, required this.info, this.onDone});
  @override
  State<LicenseScreen> createState() => _LicState();
}

class _LicState extends State<LicenseScreen> {
  final k = TextEditingController();
  String dev = '';
  String? err;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    License.deviceId().then((v) { if (mounted) setState(() => dev = v); });
  }

  Future<void> _activate() async {
    setState(() { busy = true; err = null; });
    final e = await License.activate(k.text);
    if (!mounted) return;
    if (e != null) {
      setState(() { busy = false; err = e; });
      return;
    }
    final i = await License.check();
    License.current = i;
    if (!mounted) return;
    setState(() => busy = false);
    if (i.ok) {
      snack(context, 'লাইসেন্স সক্রিয় হয়েছে ✔');
      if (widget.onDone != null) {
        widget.onDone!();
      } else {
        Navigator.maybePop(context);
      }
    } else {
      setState(() => err = i.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('লাইসেন্স ও সাবস্ক্রিপশন')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const AppLogo(size: 80),
              const SizedBox(height: 16),
              Text(widget.info.message, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.info.ok ? C.teal : C.red)),
              const SizedBox(height: 22),
              TextField(controller: k, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'লাইসেন্স কী (SSH-XXXX-XXXX)', prefixIcon: Icon(Icons.vpn_key))),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: C.red))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: busy ? null : _activate, child: busy ? const CircularProgressIndicator() : const Text('অ্যাক্টিভেট করুন'))),
              const SizedBox(height: 22),
              ListTile(
                tileColor: Theme.of(context).cardColor,
                title: const Text('ডিভাইস আইডি', style: TextStyle(fontSize: 12)),
                subtitle: Text(dev, style: const TextStyle(fontFamily: 'monospace')),
                trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: dev)); snack(context, 'কপি হয়েছে'); }),
              ),
              const SizedBox(height: 14),
              const Text(kContact, textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              if (widget.info.state == LState.blocked || widget.info.state == LState.expired)
                TextButton.icon(onPressed: widget.onDone, icon: const Icon(Icons.refresh), label: const Text('আবার যাচাই করুন')),
            ]),
          ),
        ),
      );
}
