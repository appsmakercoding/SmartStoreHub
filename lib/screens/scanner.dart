import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/ui.dart';

Future<String?> scanOnce(BuildContext c) =>
    Navigator.push<String>(c, MaterialPageRoute(builder: (_) => const ScanPage()));

/// onCode দিলে ধারাবাহিক স্ক্যান মোড: পেজ খোলা থাকে, প্রতিটি কোডের ফলাফল নিচে দেখায়।
/// onCode না দিলে একটি কোড স্ক্যান করেই ফেরত যায়।
class ScanPage extends StatefulWidget {
  final Future<String> Function(String code)? onCode;
  final String title;
  const ScanPage({super.key, this.onCode, this.title = 'বারকোড স্ক্যান করুন'});
  @override
  State<ScanPage> createState() => _ScanState();
}

class _ScanState extends State<ScanPage> {
  final controller = MobileScannerController();
  bool done = false, torch = false;
  String? last;
  DateTime? lastAt;
  String msg = '';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _handle(String code) async {
    final now = DateTime.now();
    if (last == code && lastAt != null && now.difference(lastAt!).inMilliseconds < 2000) return;
    last = code;
    lastAt = now;
    if (widget.onCode == null) {
      if (done) return;
      done = true;
      Navigator.pop(context, code);
      return;
    }
    final m = await widget.onCode!(code);
    if (mounted) setState(() => msg = m);
  }

  Future<void> _manual() async {
    final r = await askDialog(context, 'বারকোড নম্বর লিখুন', ['বারকোড'], numeric: {0});
    if (r != null && r[0].isNotEmpty) _handle(r[0]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'ফ্ল্যাশ',
              icon: Icon(torch ? Icons.flash_on : Icons.flash_off),
              onPressed: () async {
                await controller.toggleTorch();
                setState(() => torch = !torch);
              },
            ),
            IconButton(tooltip: 'হাতে লিখুন', icon: const Icon(Icons.keyboard), onPressed: _manual),
          ],
        ),
        body: Stack(children: [
          MobileScanner(
            controller: controller,
            onDetect: (cap) {
              if (cap.barcodes.isEmpty) return;
              final v = cap.barcodes.first.rawValue;
              if (v != null) _handle(v);
            },
          ),
          Center(
            child: IgnorePointer(
              child: Container(
                width: 270,
                height: 170,
                decoration: BoxDecoration(border: Border.all(color: C.gold, width: 3), borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.onCode == null ? 'বারকোড ফ্রেমের ভেতরে ধরুন' : (msg.isEmpty ? 'একের পর এক স্ক্যান করুন' : msg), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                if (widget.onCode != null) ...[
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('স্ক্যান শেষ')),
                ],
              ]),
            ),
          ),
        ]),
      );
}
