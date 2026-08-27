import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';

enum _FilterCepat { hariIni, mingguIni, bulanIni, tahunIni, custom }

class LaporanKeuanganPage extends StatefulWidget {
  const LaporanKeuanganPage({super.key});
  @override
  State<LaporanKeuanganPage> createState() => _LaporanKeuanganPageState();
}

class _LaporanKeuanganPageState extends State<LaporanKeuanganPage> {
  _FilterCepat filter = _FilterCepat.bulanIni;
  DateTimeRange? customRange;
  Map<String, dynamic> data = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _rentang() {
    final now = DateTime.now();
    switch (filter) {
      case _FilterCepat.hariIni:
        return (DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day));
      case _FilterCepat.mingguIni:
        final awalMinggu = now.subtract(Duration(days: now.weekday - 1));
        return (DateTime(awalMinggu.year, awalMinggu.month, awalMinggu.day), now);
      case _FilterCepat.bulanIni:
        return (DateTime(now.year, now.month, 1), now);
      case _FilterCepat.tahunIni:
        return (DateTime(now.year, 1, 1), now);
      case _FilterCepat.custom:
        return customRange != null ? (customRange!.start, customRange!.end) : (DateTime(now.year, now.month, 1), now);
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final (mulai, selesai) = _rentang();
    final d = await DatabaseHelper.instance.getLaporanKeuangan(mulai: mulai, selesai: selesai);
    setState(() { data = d; loading = false; });
  }

  Future<void> _pilihCustomRange() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: customRange);
    if (r != null) {
      setState(() { customRange = r; filter = _FilterCepat.custom; });
      _load();
    }
  }

  String _labelFilter(_FilterCepat f) {
    switch (f) {
      case _FilterCepat.hariIni: return 'Hari Ini';
      case _FilterCepat.mingguIni: return 'Minggu Ini';
      case _FilterCepat.bulanIni: return 'Bulan Ini';
      case _FilterCepat.tahunIni: return 'Tahun Ini';
      case _FilterCepat.custom: return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Keuangan'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final f in [_FilterCepat.hariIni, _FilterCepat.mingguIni, _FilterCepat.bulanIni, _FilterCepat.tahunIni])
                      ChoiceChip(
                        label: Text(_labelFilter(f)),
                        selected: filter == f,
                        onSelected: (_) { setState(() => filter = f); _load(); },
                        selectedColor: AppColors.biruTua,
                        labelStyle: TextStyle(color: filter == f ? Colors.white : Colors.black87, fontSize: 12),
                      ),
                    ActionChip(
                      label: Text(filter == _FilterCepat.custom && customRange != null
                          ? '${customRange!.start.day}/${customRange!.start.month} - ${customRange!.end.day}/${customRange!.end.month}'
                          : 'Custom Tanggal'),
                      avatar: const Icon(Icons.date_range, size: 16),
                      backgroundColor: filter == _FilterCepat.custom ? AppColors.biruTua.withOpacity(0.15) : null,
                      onPressed: _pilihCustomRange,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  _kartu('Total Pemasukan', data['pemasukan'], const Color(0xFF1B7A3D), Icons.trending_up),
                  const SizedBox(height: 12),
                  _kartu('Total Pengeluaran', data['pengeluaran'], const Color(0xFFB02A2A), Icons.trending_down),
                  const SizedBox(height: 12),
                  _kartu('Laba Bersih', data['laba_bersih'], AppColors.biruTua, Icons.savings),
                  const SizedBox(height: 12),
                  _kartu('Saldo (Semua Kas)', data['saldo'], const Color(0xFF854F0B), Icons.account_balance_wallet),
                  const SizedBox(height: 12),
                  _kartu('Piutang', data['piutang'], const Color(0xFF6A3FA0), Icons.receipt_long),
                ],
              ),
            ),
    );
  }

  Widget _kartu(String label, dynamic value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(formatRupiah(value), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ]),
        ),
      ]),
    );
  }
}

class LaporanTransaksiPage extends StatefulWidget {
  const LaporanTransaksiPage({super.key});
  @override
  State<LaporanTransaksiPage> createState() => _LaporanTransaksiPageState();
}

class _LaporanTransaksiPageState extends State<LaporanTransaksiPage> {
  _FilterCepat filter = _FilterCepat.bulanIni;
  DateTimeRange? customRange;
  Map<String, dynamic> data = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _rentang() {
    final now = DateTime.now();
    switch (filter) {
      case _FilterCepat.hariIni:
        return (DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day));
      case _FilterCepat.mingguIni:
        final awalMinggu = now.subtract(Duration(days: now.weekday - 1));
        return (DateTime(awalMinggu.year, awalMinggu.month, awalMinggu.day), now);
      case _FilterCepat.bulanIni:
        return (DateTime(now.year, now.month, 1), now);
      case _FilterCepat.tahunIni:
        return (DateTime(now.year, 1, 1), now);
      case _FilterCepat.custom:
        return customRange != null ? (customRange!.start, customRange!.end) : (DateTime(now.year, now.month, 1), now);
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final (mulai, selesai) = _rentang();
    final d = await DatabaseHelper.instance.getLaporanTransaksi(mulai: mulai, selesai: selesai);
    setState(() { data = d; loading = false; });
  }

  Future<void> _pilihCustomRange() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: customRange);
    if (r != null) {
      setState(() { customRange = r; filter = _FilterCepat.custom; });
      _load();
    }
  }

  String _labelFilter(_FilterCepat f) {
    switch (f) {
      case _FilterCepat.hariIni: return 'Hari Ini';
      case _FilterCepat.mingguIni: return 'Minggu Ini';
      case _FilterCepat.bulanIni: return 'Bulan Ini';
      case _FilterCepat.tahunIni: return 'Tahun Ini';
      case _FilterCepat.custom: return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Transaksi'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final f in [_FilterCepat.hariIni, _FilterCepat.mingguIni, _FilterCepat.bulanIni, _FilterCepat.tahunIni])
                      ChoiceChip(
                        label: Text(_labelFilter(f)),
                        selected: filter == f,
                        onSelected: (_) { setState(() => filter = f); _load(); },
                        selectedColor: AppColors.biruTua,
                        labelStyle: TextStyle(color: filter == f ? Colors.white : Colors.black87, fontSize: 12),
                      ),
                    ActionChip(
                      label: Text(filter == _FilterCepat.custom && customRange != null
                          ? '${customRange!.start.day}/${customRange!.start.month} - ${customRange!.end.day}/${customRange!.end.month}'
                          : 'Custom Tanggal'),
                      avatar: const Icon(Icons.date_range, size: 16),
                      backgroundColor: filter == _FilterCepat.custom ? AppColors.biruTua.withOpacity(0.15) : null,
                      onPressed: _pilihCustomRange,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: _mini('Total Transaksi', data['total_transaksi'], AppColors.biruTua)),
                    const SizedBox(width: 10),
                    Expanded(child: _mini('Selesai', data['selesai'], const Color(0xFF1B7A3D))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _mini('Proses', data['proses'], const Color(0xFF854F0B))),
                    const SizedBox(width: 10),
                    Expanded(child: _mini('Antre', data['antre'], const Color(0xFF6A3FA0))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _mini('Pending', data['pending'], Colors.grey.shade700)),
                    const SizedBox(width: 10),
                    Expanded(child: _mini('Belum Diambil', data['belum_diambil'], const Color(0xFFB5541B))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _mini('Lunas', data['lunas'], const Color(0xFF1B7A3D))),
                    const SizedBox(width: 10),
                    Expanded(child: _mini('DP', data['dp'], const Color(0xFF854F0B))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _mini('Jumlah Piutang', data['piutang_count'], const Color(0xFFB02A2A))),
                    const SizedBox(width: 10),
                    Expanded(child: _miniRp('Total Piutang', data['total_piutang'], const Color(0xFFB02A2A))),
                  ]),
                ],
              ),
            ),
    );
  }

  Widget _mini(String label, dynamic value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 6),
        Text('${value ?? 0}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _miniRp(String label, dynamic value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 6),
        Text(formatRupiah(value), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}
