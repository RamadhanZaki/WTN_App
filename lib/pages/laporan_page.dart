import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';

enum _FilterCepat { tahunIni, custom }

const _bulanNamaLaporan = ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

/// Dialog pemilih Bulan & Tahun. Mengembalikan (bulan, tahun) sesuai pilihan,
/// atau null jika dibatalkan. Rentang tahun disesuaikan dengan data pada database
/// (default: dari 2020 s.d. tahun berjalan) supaya pilihan selalu relevan dengan isi database.
Future<(int, int)?> _pilihBulanTahunDialog(BuildContext context, {int? bulanAwal, int? tahunAwal}) async {
  final now = DateTime.now();
  int bulan = bulanAwal ?? now.month;
  int tahun = tahunAwal ?? now.year;
  final tahunList = [for (int y = now.year; y >= 2020; y--) y];
  if (!tahunList.contains(tahun)) tahunList.insert(0, tahun);

  return showDialog<(int, int)>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Text('Pilih Bulan & Tahun'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Bulan'),
                    value: bulan,
                    items: [
                      for (int m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text(_bulanNamaLaporan[m])),
                    ],
                    onChanged: (v) => setStateDialog(() => bulan = v ?? bulan),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Tahun'),
                    value: tahun,
                    items: [
                      for (final y in tahunList)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setStateDialog(() => tahun = v ?? tahun),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(ctx, (bulan, tahun)), child: const Text('Pilih')),
            ],
          );
        },
      );
    },
  );
}

class LaporanKeuanganPage extends StatefulWidget {
  const LaporanKeuanganPage({super.key});
  @override
  State<LaporanKeuanganPage> createState() => _LaporanKeuanganPageState();
}

class _LaporanKeuanganPageState extends State<LaporanKeuanganPage> {
  _FilterCepat filter = _FilterCepat.custom;
  int? bulanTerpilih;
  int? tahunTerpilih;
  Map<String, dynamic> data = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    bulanTerpilih = now.month;
    tahunTerpilih = now.year;
    _load();
  }

  (DateTime, DateTime) _rentang() {
    final now = DateTime.now();
    switch (filter) {
      case _FilterCepat.tahunIni:
        return (DateTime(now.year, 1, 1), now);
      case _FilterCepat.custom:
        final b = bulanTerpilih ?? now.month;
        final t = tahunTerpilih ?? now.year;
        // Rentang satu bulan penuh: dari tanggal 1 s.d. hari terakhir bulan tsb,
        // konsisten dengan format tanggal 'yyyy-MM-dd' yang tersimpan di database.
        final akhirBulan = DateTime(t, b + 1, 0);
        return (DateTime(t, b, 1), akhirBulan);
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final (mulai, selesai) = _rentang();
    final d = await DatabaseHelper.instance.getLaporanKeuangan(mulai: mulai, selesai: selesai);
    setState(() { data = d; loading = false; });
  }

  Future<void> _pilihBulanTahun() async {
    final now = DateTime.now();
    final hasil = await _pilihBulanTahunDialog(context, bulanAwal: bulanTerpilih ?? now.month, tahunAwal: tahunTerpilih ?? now.year);
    if (hasil != null) {
      setState(() { bulanTerpilih = hasil.$1; tahunTerpilih = hasil.$2; filter = _FilterCepat.custom; });
      _load();
    }
  }

  String _labelFilter(_FilterCepat f) {
    switch (f) {
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
                    for (final f in [_FilterCepat.tahunIni])
                      ChoiceChip(
                        label: Text(_labelFilter(f)),
                        selected: filter == f,
                        onSelected: (_) { setState(() => filter = f); _load(); },
                        selectedColor: AppColors.biruTua,
                        labelStyle: TextStyle(color: filter == f ? Colors.white : Colors.black87, fontSize: 12),
                      ),
                    ActionChip(
                      label: Text(filter == _FilterCepat.custom && bulanTerpilih != null && tahunTerpilih != null
                          ? '${_bulanNamaLaporan[bulanTerpilih!]} $tahunTerpilih'
                          : 'Pilih Bulan'),
                      avatar: const Icon(Icons.calendar_month, size: 16),
                      backgroundColor: filter == _FilterCepat.custom ? AppColors.biruTua.withOpacity(0.15) : null,
                      onPressed: _pilihBulanTahun,
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
  _FilterCepat filter = _FilterCepat.custom;
  int? bulanTerpilih;
  int? tahunTerpilih;
  Map<String, dynamic> data = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    bulanTerpilih = now.month;
    tahunTerpilih = now.year;
    _load();
  }

  (DateTime, DateTime) _rentang() {
    final now = DateTime.now();
    switch (filter) {
      case _FilterCepat.tahunIni:
        return (DateTime(now.year, 1, 1), now);
      case _FilterCepat.custom:
        final b = bulanTerpilih ?? now.month;
        final t = tahunTerpilih ?? now.year;
        final akhirBulan = DateTime(t, b + 1, 0);
        return (DateTime(t, b, 1), akhirBulan);
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final (mulai, selesai) = _rentang();
    final d = await DatabaseHelper.instance.getLaporanTransaksi(mulai: mulai, selesai: selesai);
    setState(() { data = d; loading = false; });
  }

  Future<void> _pilihBulanTahun() async {
    final now = DateTime.now();
    final hasil = await _pilihBulanTahunDialog(context, bulanAwal: bulanTerpilih ?? now.month, tahunAwal: tahunTerpilih ?? now.year);
    if (hasil != null) {
      setState(() { bulanTerpilih = hasil.$1; tahunTerpilih = hasil.$2; filter = _FilterCepat.custom; });
      _load();
    }
  }

  String _labelFilter(_FilterCepat f) {
    switch (f) {
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
                    for (final f in [_FilterCepat.tahunIni])
                      ChoiceChip(
                        label: Text(_labelFilter(f)),
                        selected: filter == f,
                        onSelected: (_) { setState(() => filter = f); _load(); },
                        selectedColor: AppColors.biruTua,
                        labelStyle: TextStyle(color: filter == f ? Colors.white : Colors.black87, fontSize: 12),
                      ),
                    ActionChip(
                      label: Text(filter == _FilterCepat.custom && bulanTerpilih != null && tahunTerpilih != null
                          ? '${_bulanNamaLaporan[bulanTerpilih!]} $tahunTerpilih'
                          : 'Pilih Bulan'),
                      avatar: const Icon(Icons.calendar_month, size: 16),
                      backgroundColor: filter == _FilterCepat.custom ? AppColors.biruTua.withOpacity(0.15) : null,
                      onPressed: _pilihBulanTahun,
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
