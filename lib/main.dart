import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'pages/dashboard_page.dart';
import 'pages/transaksi_page.dart';
import 'pages/order_form_page.dart';
import 'pages/kas_keluar_page.dart';
import 'pages/lainnya_page.dart';

void main() {
  runApp(const WtnBlastingApp());
}

class WtnBlastingApp extends StatelessWidget {
  const WtnBlastingApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WTN Blasting',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.biruTua),
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0, centerTitle: false, iconTheme: IconThemeData(color: Colors.black)),
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  Widget _buildBody() {
    switch (_index) {
      case 0: return const DashboardPage();
      case 1: return const TransaksiPage();
      case 3: return const KasKeluarPage();
      case 4: return const LainnyaPage();
      default: return const DashboardPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.biruTua,
        shape: const CircleBorder(),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderFormPage()));
          setState(() {});
        },
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _navItem(0, Icons.home, 'Dashboard'),
          _navItem(1, Icons.receipt_long, 'Transaksi'),
          const SizedBox(width: 40),
          _navItem(3, Icons.payments, 'Kas'),
          _navItem(4, Icons.apps, 'Lainnya'),
        ]),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final selected = _index == i;
    return InkWell(
      onTap: () => setState(() => _index = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: selected ? AppColors.biruTua : Colors.grey, size: 24),
          Text(label, style: TextStyle(fontSize: 10, color: selected ? AppColors.biruTua : Colors.grey)),
        ]),
      ),
    );
  }
}