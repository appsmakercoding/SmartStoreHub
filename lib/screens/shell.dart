import 'package:flutter/material.dart';
import '../core/db.dart';
import 'customers.dart';
import 'dashboard.dart';
import 'home.dart';
import 'more.dart';
import 'pos.dart';
import 'products.dart';
import 'reports.dart';

class _Tab {
  final String label;
  final IconData icon;
  final Widget page;
  _Tab(this.label, this.icon, this.page);
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _ShellState();
}

class _ShellState extends State<MainShell> {
  int idx = 0;

  void _logout() async {
    await Db.log('লগআউট');
    Session.user = null;
    PosScreen.cart.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = Session.role == 'cashier'
        ? [
            _Tab('বিক্রি', Icons.point_of_sale, const PosScreen()),
            _Tab('পণ্য', Icons.inventory_2, const ProductsScreen()),
            _Tab('আমার হিসাব', Icons.bar_chart, const ReportsScreen(mine: true)),
          ]
        : [
            _Tab('ড্যাশবোর্ড', Icons.dashboard, const DashboardScreen()),
            _Tab('বিক্রি', Icons.point_of_sale, const PosScreen()),
            _Tab('পণ্য', Icons.inventory_2, const ProductsScreen()),
            _Tab('গ্রাহক', Icons.people, const CustomersScreen()),
            _Tab('আরও', Icons.menu, const MoreScreen()),
          ];
    return Scaffold(
      appBar: AppBar(
        title: Text('${tabs[idx].label} • ${Session.name}'),
        actions: [IconButton(icon: const Icon(Icons.logout), tooltip: 'লগআউট', onPressed: _logout)],
      ),
      body: tabs[idx].page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label)],
      ),
    );
  }
}
