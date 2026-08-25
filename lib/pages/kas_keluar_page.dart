import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';

class KasKeluarPage extends StatefulWidget {
  const KasKeluarPage({super.key});
  @override
  State<KasKeluarPage> createState() => _KasKeluarPageState();
}

class _KasKeluarPageState extends State<KasKeluarPage> {
  Map<String, double> saldo = {'kas': 0, 'vapor': 0, 'alat': 0};
  String jenis = 'kas';
  final _nominal = TextEditingController();
  final _catatan = TextEditingController();
  bool loading = true;
  bool saving = false;

  // Riwayat pengeluaran per bulan
  List<Map<String, dynamic>> riwayat = [];
  bool loadingRiwayat = true;
  int bulanFilter = DateTime.now().month;
  int tahunFilter = DateTime.now().year;

  final bulanNama = const ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  @override
  void initState() {
    super.initState();
    _load();
    _loadRiwayat();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final s = await DatabaseHelper.instance.getSaldoTerakhir();
    setState(() {
      saldo = s;
      loading = false;
    });
  }

  Future<void> _loadRiwayat() async {
    setState(() => loadingRiwayat = true);
    final r = await DatabaseHelper.instance.getPengeluaranByBulan(bulanFilter, tahunFilter);
    setState(() {
      riwayat = r;
      loadingRiwayat = false;
    });
  }

  double get _totalRiwayat => riwayat.fold(0.0, (sum, r) => sum + (((r['nominal'] as num?) ?? 0).toDouble()));

  Future<void> _pilihBulanFilter() async {
    int tempBulan = bulanFilter;
    int tempTahun = tahunFilter;
    final tahunList = List.generate(6, (i) => DateTime.now().year - 3 + i);

    final hasil = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Pilih Bulan & Tahun'),
          content: Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: tempBulan,
                decoration: const InputDecoration(labelText: 'Bulan', isDense: true),
                items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(bulanNama[i + 1]))),
                onChanged: (v) => setDialogState(() => tempBulan = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: tempTahun,
                decoration: const InputDecoration(labelText: 'Tahun', isDense: true),
                items: tahunList.map((t) => DropdownMenuItem(value: t, child: Text('$t'))).toList(),
                onChanged: (v) => setDialogState(() => tempTahun = v!),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {'bulan': tempBulan, 'tahun': tempTahun}),
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );

    if (hasil != null) {
      setState(() {
        bulanFilter = hasil['bulan']!;
        tahunFilter = hasil['tahun']!;
      });
      await _loadRiwayat();
    }
  }

  Future<void> _simpan() async {
    final nominal = double.tryParse(_nominal.text.trim()) ?? 0;
    if (nominal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi nominal terlebih dahulu')));
      return;
    }
    setState(() => saving = true);
    await DatabaseHelper.instance.insertPengeluaran(
      jenis: jenis,
      nominal: nominal,
      catatan: _catatan.text.trim(),
      tanggal: DateTime.now().toIso8601String().substring(0, 10),
    );
    _nominal.clear();
    _catatan.clear();
    await _load();
    // Refresh riwayat hanya kalau pengeluaran baru masuk ke bulan & tahun
    // yang sedang difilter, supaya tidak melakukan query yang tidak perlu.
    final sekarang = DateTime.now();
    if (bulanFilter == sekarang.month && tahunFilter == sekarang.year) {
      await _loadRiwayat();
    }
    setState(() => saving = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengeluaran tersimpan')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _load();
                await _loadRiwayat();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    _saldoCard('Saldo KAS', saldo['kas']),
                    const SizedBox(width: 8),
                    _saldoCard('KAS Vapor', saldo['vapor']),
                    const SizedBox(width: 8),
                    _saldoCard('KAS Maintenance', saldo['alat']),
                  ]),
                  const SizedBox(height: 20),
                  const Text('Jenis kas', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: jenis,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'kas', child: Text('KAS umum')),
                      DropdownMenuItem(value: 'vapor', child: Text('KAS Vapor')),
                      DropdownMenuItem(value: 'alat', child: Text('KAS Maintenance')),
                    ],
                    onChanged: (v) => setState(() => jenis = v ?? 'kas'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nominal,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Nominal', hintText: 'Rp0', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _catatan,
                    decoration: const InputDecoration(labelText: 'Catatan', hintText: 'cth. Beli bubuk hitam', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: saving ? null : _simpan,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Simpan Pengeluaran'),
                  ),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 8),
                  _riwayatSection(),
                ],
              ),
            ),
    );
  }

  Widget _riwayatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Riwayat Pengeluaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          InkWell(
            onTap: _pilihBulanFilter,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: AppColors.biruTua.withOpacity(0.4)), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_month, size: 14, color: AppColors.biruTua),
                const SizedBox(width: 4),
                Text('${bulanNama[bulanFilter]} $tahunFilter', style: TextStyle(fontSize: 12, color: AppColors.biruTua, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (loadingRiwayat)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
        else if (riwayat.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Belum ada pengeluaran di bulan ${bulanNama[bulanFilter]} $tahunFilter', style: const TextStyle(color: Colors.grey)),
            ),
          )
        else ...[
          ...riwayat.map(_riwayatTile),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: AppColors.hitamLogo, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total Pengeluaran ${bulanNama[bulanFilter]} $tahunFilter', style: TextStyle(color: AppColors.biruTerang.withOpacity(0.9), fontSize: 12)),
              Text(formatRupiah(_totalRiwayat), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _riwayatTile(Map<String, dynamic> r) {
    final catatan = (r['catatan'] as String?)?.trim();
    final sumber = (r['sumber'] as String?) ?? '-';
    final tanggal = (r['tanggal'] as String?) ?? '-';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: AppColors.hitamLogo, child: Icon(Icons.arrow_upward, color: AppColors.biruTerang, size: 18)),
        title: Text(catatan == null || catatan.isEmpty ? '(Tanpa catatan)' : catatan, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text('$tanggal  •  Diambil dari: $sumber', style: const TextStyle(fontSize: 12)),
        trailing: Text(formatRupiah(r['nominal']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.redAccent)),
      ),
    );
  }

  Widget _saldoCard(String label, double? value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(formatRupiah(value ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}