import 'dart:async';
import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';
import 'detail_transaksi_page.dart';

class TransaksiPage extends StatefulWidget {
  const TransaksiPage({super.key});
  @override
  State<TransaksiPage> createState() => _TransaksiPageState();
}

class _TransaksiPageState extends State<TransaksiPage> {
  int bulan = DateTime.now().month;
  int tahun = DateTime.now().year;
  String search = '';
  List<Map<String, dynamic>> data = [];
  bool loading = true;
  Timer? _debounce;

  // Filter tambahan
  String? filterStatusPengerjaan;
  String? filterStatusPengambilan;
  String? filterStatusPembayaran;
  String? filterMotor;
  String? filterProses;
  DateTimeRange? filterTanggal;
  List<Map<String, dynamic>> masterMotor = [];
  List<Map<String, dynamic>> masterProses = [];

  bool get adaFilterAktif =>
      filterStatusPengerjaan != null || filterStatusPengambilan != null || filterStatusPembayaran != null ||
      filterMotor != null || filterProses != null || filterTanggal != null;

  final bulanNama = const ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  @override
  void initState() {
    super.initState();
    _load();
    _loadMaster();
  }

  Future<void> _loadMaster() async {
    masterMotor = await DatabaseHelper.instance.getMaster('master_motor');
    masterProses = await DatabaseHelper.instance.getMaster('master_proses');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final d = adaFilterAktif || search.isNotEmpty
        ? await DatabaseHelper.instance.cariTransaksi(
            bulan: filterTanggal == null ? bulan : null,
            tahun: filterTanggal == null ? tahun : null,
            search: search,
            statusPengerjaan: filterStatusPengerjaan,
            statusPengambilan: filterStatusPengambilan,
            statusPembayaran: filterStatusPembayaran,
            motor: filterMotor,
            proses: filterProses,
            tanggalMulai: filterTanggal?.start,
            tanggalSelesai: filterTanggal?.end,
          )
        : await DatabaseHelper.instance.getTransaksiByBulan(bulan, tahun, search: search);
    setState(() { data = d; loading = false; });
  }

  Future<void> _bukaFilter() async {
    String? tmpPengerjaan = filterStatusPengerjaan;
    String? tmpPengambilan = filterStatusPengambilan;
    String? tmpPembayaran = filterStatusPembayaran;
    String? tmpMotor = filterMotor;
    String? tmpProses = filterProses;
    DateTimeRange? tmpTanggal = filterTanggal;

    final hasil = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Filter Transaksi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, false)),
              ]),
              const SizedBox(height: 8),
              const Text('Status Pengerjaan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: tmpPengerjaan,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Semua')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'antre', child: Text('Antre')),
                  DropdownMenuItem(value: 'proses', child: Text('Proses')),
                  DropdownMenuItem(value: 'selesai', child: Text('Selesai')),
                ],
                onChanged: (v) => setSheetState(() => tmpPengerjaan = v),
              ),
              const SizedBox(height: 12),
              const Text('Status Pengambilan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: tmpPengambilan,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Semua')),
                  DropdownMenuItem(value: 'belum_diambil', child: Text('Belum Diambil')),
                  DropdownMenuItem(value: 'sudah_diambil', child: Text('Sudah Diambil')),
                ],
                onChanged: (v) => setSheetState(() => tmpPengambilan = v),
              ),
              const SizedBox(height: 12),
              const Text('Status Pembayaran', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: tmpPembayaran,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Semua')),
                  DropdownMenuItem(value: 'belum_bayar', child: Text('Belum Bayar')),
                  DropdownMenuItem(value: 'dp', child: Text('DP')),
                  DropdownMenuItem(value: 'lunas', child: Text('Lunas')),
                  DropdownMenuItem(value: 'piutang', child: Text('Piutang')),
                ],
                onChanged: (v) => setSheetState(() => tmpPembayaran = v),
              ),
              const SizedBox(height: 12),
              const Text('Type Motor', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: tmpMotor,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Semua')),
                  ...masterMotor.map((m) => DropdownMenuItem<String?>(value: m['nama'] as String, child: Text(m['nama']))),
                ],
                onChanged: (v) => setSheetState(() => tmpMotor = v),
              ),
              const SizedBox(height: 12),
              const Text('Proses', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: tmpProses,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Semua')),
                  ...masterProses.map((m) => DropdownMenuItem<String?>(value: m['nama'] as String, child: Text(m['nama']))),
                ],
                onChanged: (v) => setSheetState(() => tmpProses = v),
              ),
              const SizedBox(height: 12),
              const Text('Rentang Tanggal', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final r = await showDateRangePicker(
                    context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2100),
                    initialDateRange: tmpTanggal,
                  );
                  if (r != null) setSheetState(() => tmpTanggal = r);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(
                      tmpTanggal == null
                          ? 'Pakai filter Bulan/Tahun di atas'
                          : '${tmpTanggal!.start.day}/${tmpTanggal!.start.month}/${tmpTanggal!.start.year} - ${tmpTanggal!.end.day}/${tmpTanggal!.end.month}/${tmpTanggal!.end.year}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (tmpTanggal != null) IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setSheetState(() => tmpTanggal = null))
                    else const Icon(Icons.date_range, size: 18, color: Colors.grey),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setSheetState(() {
                      tmpPengerjaan = null; tmpPengambilan = null; tmpPembayaran = null;
                      tmpMotor = null; tmpProses = null; tmpTanggal = null;
                    }),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua),
                    onPressed: () {
                      filterStatusPengerjaan = tmpPengerjaan;
                      filterStatusPengambilan = tmpPengambilan;
                      filterStatusPembayaran = tmpPembayaran;
                      filterMotor = tmpMotor;
                      filterProses = tmpProses;
                      filterTanggal = tmpTanggal;
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('Terapkan Filter'),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );

    if (hasil == true) _load();
  }

  // Ketik pencarian sebelumnya langsung memanggil _load() (query DB berat)
  // di SETIAP huruf yang diketik. Sekarang di-debounce 400ms supaya query
  // hanya dijalankan setelah user berhenti mengetik sesaat.
  void _onSearchChanged(String v) {
    search = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) {
    final tahunList = List.generate(6, (i) => DateTime.now().year - 3 + i);
    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: bulan,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(bulanNama[i + 1]))),
                    onChanged: filterTanggal != null ? null : (v) { setState(() => bulan = v!); _load(); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: tahun,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: tahunList.map((t) => DropdownMenuItem(value: t, child: Text('$t'))).toList(),
                    onChanged: filterTanggal != null ? null : (v) { setState(() => tahun = v!); _load(); },
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(hintText: 'Cari No/nama/motor/barang/proses...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _bukaFilter,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: adaFilterAktif ? AppColors.biruTua : Colors.white,
                      border: Border.all(color: adaFilterAktif ? AppColors.biruTua : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.filter_list, size: 20, color: adaFilterAktif ? Colors.white : Colors.grey.shade700),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Total ${data.length} Transaksi', style: const TextStyle(color: Colors.grey))),
                if (adaFilterAktif)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        filterStatusPengerjaan = null; filterStatusPengambilan = null; filterStatusPembayaran = null;
                        filterMotor = null; filterProses = null; filterTanggal = null;
                      });
                      _load();
                    },
                    icon: const Icon(Icons.clear, size: 14),
                    label: const Text('Hapus Filter', style: TextStyle(fontSize: 12)),
                  ),
              ]),
            ]),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? const Center(child: Text('Belum ada transaksi bulan ini'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: data.length,
                        itemBuilder: (_, i) => _card(data[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> t) {
    final status = (t['status'] ?? 'pending') as String;
    final statusBayar = (t['status_pembayaran'] ?? 'belum_bayar') as String;
    final statusAmbil = (t['status_pengambilan'] ?? 'belum_diambil') as String;
    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailTransaksiPage(orderId: t['id'])));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('#${t['no_transaksi'] ?? '-'}', style: TextStyle(color: AppColors.biruTua, fontWeight: FontWeight.bold)),
              Text(t['tanggal'] ?? '-', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            _baris('Nama', t['asal']),
            _baris('Motor', t['motor']),
            _baris('Barang', t['daftar_barang']),
            _baris('Proses', t['proses']),
            _baris('Harga', formatRupiah(t['total_harga'])),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _badge(AppColors.statusLabel(status), AppColors.statusBg(status), AppColors.statusText(status)),
              _badge(AppColors.ambilLabel(statusAmbil), AppColors.ambilBg(statusAmbil), AppColors.ambilText(statusAmbil)),
              _badge(AppColors.bayarLabel(statusBayar), AppColors.bayarBg(statusBayar), AppColors.bayarText(statusBayar)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _baris(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
        Expanded(child: Text('${value ?? '-'}', style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}