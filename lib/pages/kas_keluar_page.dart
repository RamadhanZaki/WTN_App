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
  String? jenisKasFilter; // null = semua
  DateTimeRange? tanggalFilter; // kalau diisi, menggantikan bulan/tahun

  // Bulan/Tahun yang tersedia HANYA dari periode yang benar-benar ada
  // baris pengeluarannya di database (bukan daftar tetap 12 bulan/6 tahun).
  List<int> tahunPengeluaranTersedia = [DateTime.now().year];
  List<int> bulanPengeluaranTersedia = [DateTime.now().month];

  final bulanNama = const ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  @override
  void initState() {
    super.initState();
    _load();
    _initFilterRiwayat();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final s = await DatabaseHelper.instance.getSaldoTerakhir();
    setState(() {
      saldo = s;
      loading = false;
    });
  }

  // Menentukan bulan/tahun default riwayat berdasarkan data yang benar-benar
  // ada (sama seperti halaman Transaksi): kalau belum ada pengeluaran sama
  // sekali, tetap pakai bulan/tahun sekarang; kalau ada tapi periode
  // sekarang kosong, pindah otomatis ke periode terbaru yang ada datanya.
  Future<void> _initFilterRiwayat() async {
    final tahunList = await DatabaseHelper.instance.getTahunPengeluaranTersedia();
    if (tahunList.isEmpty) {
      await _loadRiwayat();
      return;
    }

    tahunPengeluaranTersedia = tahunList;
    if (!tahunPengeluaranTersedia.contains(tahunFilter)) tahunFilter = tahunPengeluaranTersedia.first;

    final bulanList = await DatabaseHelper.instance.getBulanPengeluaranTersedia(tahunFilter);
    bulanPengeluaranTersedia = bulanList.isEmpty ? [bulanFilter] : bulanList;
    if (!bulanPengeluaranTersedia.contains(bulanFilter)) bulanFilter = bulanPengeluaranTersedia.first;

    if (mounted) setState(() {});
    await _loadRiwayat();
  }

  Future<void> _loadRiwayat() async {
    setState(() => loadingRiwayat = true);
    final r = await DatabaseHelper.instance.getPengeluaranByBulan(
      bulanFilter, tahunFilter,
      jenisKas: jenisKasFilter,
      tanggalMulai: tanggalFilter?.start,
      tanggalSelesai: tanggalFilter?.end,
    );
    setState(() {
      riwayat = r;
      loadingRiwayat = false;
    });
  }

  Future<void> _pilihJenisKasFilter() async {
    final hasil = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text('Semua Jenis Kas'), onTap: () => Navigator.pop(ctx, '')),
        ListTile(title: const Text('KAS Umum'), onTap: () => Navigator.pop(ctx, 'kas')),
        ListTile(title: const Text('KAS Vapor'), onTap: () => Navigator.pop(ctx, 'vapor')),
        ListTile(title: const Text('KAS Maintenance'), onTap: () => Navigator.pop(ctx, 'alat')),
      ]),
    );
    if (hasil != null) {
      setState(() => jenisKasFilter = hasil.isEmpty ? null : hasil);
      await _loadRiwayat();
    }
  }

  Future<void> _pilihRentangTanggal() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: tanggalFilter);
    if (r != null) {
      setState(() => tanggalFilter = r);
      await _loadRiwayat();
    }
  }

  double get _totalRiwayat => riwayat.fold(0.0, (sum, r) => sum + (((r['nominal'] as num?) ?? 0).toDouble()));

  Future<void> _pilihBulanFilter() async {
    int tempBulan = bulanFilter;
    int tempTahun = tahunFilter;
    List<int> tempBulanTersedia = List<int>.from(bulanPengeluaranTersedia);

    final hasil = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Pilih Bulan & Tahun'),
          content: Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('dlgbulan-${tempBulanTersedia.join(",")}-$tempBulan'),
                initialValue: tempBulan,
                decoration: const InputDecoration(labelText: 'Bulan', isDense: true),
                items: (List<int>.from(tempBulanTersedia)..sort()).map((b) => DropdownMenuItem(value: b, child: Text(bulanNama[b]))).toList(),
                onChanged: (v) => setDialogState(() => tempBulan = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('dlgtahun-${tahunPengeluaranTersedia.join(",")}-$tempTahun'),
                initialValue: tempTahun,
                decoration: const InputDecoration(labelText: 'Tahun', isDense: true),
                items: tahunPengeluaranTersedia.map((t) => DropdownMenuItem(value: t, child: Text('$t'))).toList(),
                onChanged: (v) async {
                  setDialogState(() => tempTahun = v!);
                  final bl = await DatabaseHelper.instance.getBulanPengeluaranTersedia(v!);
                  setDialogState(() {
                    tempBulanTersedia = bl.isEmpty ? [tempBulan] : bl;
                    if (!tempBulanTersedia.contains(tempBulan)) tempBulan = tempBulanTersedia.first;
                  });
                },
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

  Future<void> _bukaPenyesuaianSaldo() async {
    String jenisTerpilih = 'kas';
    final saldoC = TextEditingController();
    final alasanC = TextEditingController();

    final hasil = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Penyesuaian Saldo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, false)),
              ]),
              const SizedBox(height: 4),
              const Text('Gunakan ini untuk mengoreksi selisih saldo sistem dengan saldo aktual (mis. pengeluaran lama yang belum tercatat).', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: jenisTerpilih,
                decoration: const InputDecoration(labelText: 'Jenis Kas', border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'kas', child: Text('KAS Umum')),
                  DropdownMenuItem(value: 'vapor', child: Text('KAS Vapor')),
                  DropdownMenuItem(value: 'alat', child: Text('KAS Maintenance')),
                ],
                onChanged: (v) => setSheetState(() => jenisTerpilih = v ?? 'kas'),
              ),
              const SizedBox(height: 8),
              Text('Saldo sistem saat ini: ${formatRupiah(saldo[jenisTerpilih] ?? 0)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: saldoC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Saldo Aktual Sekarang', hintText: 'Rp0', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: alasanC,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Alasan Penyesuaian (wajib)', hintText: 'cth. Pengeluaran sebelumnya tidak tercatat', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua, minimumSize: const Size(double.infinity, 46)),
                onPressed: () {
                  final saldoAktual = double.tryParse(saldoC.text.trim());
                  if (saldoAktual == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Isi saldo aktual dengan angka yang benar')));
                    return;
                  }
                  if (alasanC.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Alasan penyesuaian wajib diisi')));
                    return;
                  }
                  Navigator.pop(ctx, true);
                  _prosesPenyesuaian(jenisTerpilih, saldoAktual, alasanC.text.trim());
                },
                child: const Text('Simpan Penyesuaian'),
              ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
    if (hasil == null) return;
  }

  Future<void> _prosesPenyesuaian(String jenis, double saldoAktual, String alasan) async {
    await DatabaseHelper.instance.tambahPenyesuaianSaldo(jenisKas: jenis, saldoAktual: saldoAktual, alasan: alasan);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Penyesuaian saldo tersimpan')));
  }

  Future<void> _lihatHistoriPenyesuaian() async {
    final histori = await DatabaseHelper.instance.getHistoriPenyesuaianSaldo();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.9, expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Histori Penyesuaian Saldo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: histori.isEmpty
                  ? const Center(child: Text('Belum ada penyesuaian saldo', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: histori.length,
                      itemBuilder: (_, i) {
                        final h = histori[i];
                        final nominal = (h['nominal_penyesuaian'] as num?)?.toDouble() ?? 0;
                        final jenisLabel = h['jenis_kas'] == 'kas' ? 'KAS Umum' : h['jenis_kas'] == 'vapor' ? 'KAS Vapor' : 'KAS Maintenance';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            title: Text('$jenisLabel • ${nominal >= 0 ? '+' : ''}${formatRupiah(nominal)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('${h['tanggal']}\n${h['alasan']}\nSaldo: ${formatRupiah(h['saldo_sebelum'])} → ${formatRupiah(h['saldo_sesudah'])}', style: const TextStyle(fontSize: 11)),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _bukaResetPeriode() async {
    final totalSekarang = (saldo['kas'] ?? 0) + (saldo['vapor'] ?? 0) + (saldo['alat'] ?? 0);
    final alasanC = TextEditingController();
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Periode Pembukuan?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Saldo akhir periode saat ini (${formatRupiah(totalSekarang)}) akan disimpan ke riwayat, lalu saldo dimulai ulang dari Rp0 untuk periode baru.', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          const Text('Histori transaksi & pengeluaran lama TIDAK dihapus.', style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          TextField(controller: alasanC, decoration: const InputDecoration(labelText: 'Keterangan (opsional)', border: OutlineInputBorder(), isDense: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya, Reset')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    await DatabaseHelper.instance.resetPeriode(keterangan: alasanC.text.trim());
    await _load();
    await _loadRiwayat();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Periode baru dimulai, saldo awal Rp0')));
  }

  Future<void> _lihatRiwayatPeriode() async {
    final list = await DatabaseHelper.instance.getRiwayatPeriode();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.9, expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Riwayat Reset Periode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Belum pernah reset periode', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        final total = ((r['saldo_akhir_kas'] as num?) ?? 0) + ((r['saldo_akhir_vapor'] as num?) ?? 0) + ((r['saldo_akhir_alat'] as num?) ?? 0);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            title: Text('${r['tanggal']} • Saldo akhir: ${formatRupiah(total)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('KAS: ${formatRupiah(r['saldo_akhir_kas'])} • Vapor: ${formatRupiah(r['saldo_akhir_vapor'])} • Maintenance: ${formatRupiah(r['saldo_akhir_alat'])}${(r['keterangan'] as String?)?.isNotEmpty == true ? '\n${r['keterangan']}' : ''}', style: const TextStyle(fontSize: 11)),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
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
    // Refresh daftar bulan/tahun yang tersedia (siapa tahu ini pengeluaran
    // pertama di bulan berjalan, jadi perlu muncul di pilihan filter).
    // _initFilterRiwayat mempertahankan bulan/tahun yang sedang dilihat user
    // selama masih valid, dan hanya pindah ke periode terbaru kalau filter
    // lama sudah tidak ada datanya sama sekali.
    await _initFilterRiwayat();
    setState(() => saving = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengeluaran tersimpan')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran'), actions: [
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'penyesuaian') _bukaPenyesuaianSaldo();
            if (v == 'histori_penyesuaian') _lihatHistoriPenyesuaian();
            if (v == 'reset_periode') _bukaResetPeriode();
            if (v == 'riwayat_periode') _lihatRiwayatPeriode();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'penyesuaian', child: Text('Penyesuaian Saldo')),
            PopupMenuItem(value: 'histori_penyesuaian', child: Text('Histori Penyesuaian')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'reset_periode', child: Text('Reset Periode Baru')),
            PopupMenuItem(value: 'riwayat_periode', child: Text('Riwayat Reset Periode')),
          ],
        ),
      ]),
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
        const Text('Riwayat Pengeluaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          InkWell(
            onTap: tanggalFilter != null ? null : _pilihBulanFilter,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: AppColors.biruTua.withOpacity(tanggalFilter != null ? 0.15 : 0.4)), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_month, size: 14, color: AppColors.biruTua.withOpacity(tanggalFilter != null ? 0.4 : 1)),
                const SizedBox(width: 4),
                Text('${bulanNama[bulanFilter]} $tahunFilter', style: TextStyle(fontSize: 12, color: AppColors.biruTua.withOpacity(tanggalFilter != null ? 0.4 : 1), fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          InkWell(
            onTap: _pilihRentangTanggal,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.date_range, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  tanggalFilter == null ? 'Rentang Tanggal' : '${tanggalFilter!.start.day}/${tanggalFilter!.start.month} - ${tanggalFilter!.end.day}/${tanggalFilter!.end.month}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (tanggalFilter != null)
                  GestureDetector(
                    onTap: () { setState(() => tanggalFilter = null); _loadRiwayat(); },
                    child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.clear, size: 14)),
                  ),
              ]),
            ),
          ),
          InkWell(
            onTap: _pilihJenisKasFilter,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: jenisKasFilter != null ? AppColors.biruTua : Colors.white,
                border: Border.all(color: jenisKasFilter != null ? AppColors.biruTua : Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.filter_alt, size: 14, color: jenisKasFilter != null ? Colors.white : Colors.grey),
                const SizedBox(width: 4),
                Text(
                  jenisKasFilter == null ? 'Semua Kas' : (jenisKasFilter == 'kas' ? 'KAS Umum' : jenisKasFilter == 'vapor' ? 'KAS Vapor' : 'KAS Maintenance'),
                  style: TextStyle(fontSize: 12, color: jenisKasFilter != null ? Colors.white : Colors.black87),
                ),
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