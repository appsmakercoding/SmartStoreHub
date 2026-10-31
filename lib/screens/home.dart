import 'package:flutter/material.dart';
import '../core/logo.dart';
import '../core/ui.dart';
import '../core/license.dart';
import 'gate.dart';
import 'login.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [C.dark, C.teal], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: SafeArea(
            child: Column(children: [
              const SizedBox(height: 36),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.5, end: 1),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.elasticOut,
                builder: (c, v, _) => Transform.scale(scale: v, child: const AppLogo(size: 110)),
              ),
              const SizedBox(height: 16),
              const Text('SmartStoreHub', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 4),
              const Text('আপনার সুপার শপের স্মার্ট ম্যানেজমেন্ট', style: TextStyle(color: Colors.white70, fontSize: 13)),
              if (License.current != null && (License.current!.state == LState.trial || (License.current!.state == LState.active && License.current!.daysLeft <= 7)))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ActionChip(
                    backgroundColor: C.gold,
                    avatar: const Icon(Icons.timer, size: 18),
                    label: Text('${License.current!.state == LState.trial ? 'ট্রায়াল' : 'মেয়াদ'}: ${License.current!.daysLeft} দিন বাকি • লাইসেন্স নিন'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LicenseScreen(info: License.current!, onDone: () => Navigator.pop(context)))),
                  ),
                ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(padding: const EdgeInsets.symmetric(horizontal: 22), children: const [
                  _RoleCard('admin', 'এডমিন লগইন', 'মালিক • সম্পূর্ণ নিয়ন্ত্রণ ও রিপোর্ট', Icons.admin_panel_settings),
                  _RoleCard('manager', 'ম্যানেজার লগইন', 'দোকানের কার্যক্রম ও ফলাফল', Icons.manage_accounts),
                  _RoleCard('cashier', 'ক্যাশিয়ার লগইন', 'বিল, মালামাল এন্ট্রি ও বারকোড', Icons.point_of_sale),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'Powered by ', style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13)),
                  const TextSpan(text: 'Hasan', style: TextStyle(color: C.gold, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.2)),
                ])),
              ),
            ]),
          ),
        ),
      );
}

class _RoleCard extends StatelessWidget {
  final String role, title, sub;
  final IconData icon;
  const _RoleCard(this.role, this.title, this.sub, this.icon);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(role: role))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.teal.withAlpha(25), borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: C.teal, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(sub, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ]),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16, color: C.gold),
              ]),
            ),
          ),
        ),
      );
}
