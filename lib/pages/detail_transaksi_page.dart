import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database_helper.dart';
import '../app_theme.dart';
import 'order_form_page.dart';

class DetailTransaksiPage extends StatefulWidget {
  final int orderId;
  const DetailTransaksiPage({super.key, required this.orderId});
  @override
  State<DetailTransaksiPage> createState() => _DetailTransaksiPageState();
}

class _DetailTransaksiPageState extends State<DetailTransaksiPage> {
  Map<String, dynamic>? data;
  bool loading = true;

  final bulanNama = const ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final d = await DatabaseHelper.instance.getTransaksiDetail(widget.orderId);
    setState(() {
      data = d;
      loading = false;
    });
  }

  double get totalHarga => (data?['total_harga'] as num?)?.toDouble() ?? 0;
  double get totalDibayar => (data?['total_dibayar'] as num?)?.toDouble() ?? 0;
  double get sisa => (totalHarga - totalDibayar).clamp(0, double.infinity);
  String get statusPengerjaan => (data?['status'] as String?) ?? 'pending';
  String get statusPembayaran => (data?['status_pembayaran'] as String?) ?? 'belum_bayar';
  String get statusPengambilan => (data?['status_pengambilan'] as String?) ?? 'belum_diambil';

  Future<void> _ubahStatus() async {
    String tempPengerjaan = statusPengerjaan;
    String tempPengambilan = statusPengambilan;

    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ubah Status'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Status Pengerjaan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: tempPengerjaan,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'antre', child: Text('Antre')),
                DropdownMenuItem(value: 'proses', child: Text('On Proses')),
                DropdownMenuItem(value: 'selesai', child: Text('Selesai')),
              ],
              onChanged: (v) => setDialogState(() {
                tempPengerjaan = v ?? tempPengerjaan;
                // Kalau status pengerjaan diturunkan lagi dari Selesai, status
                // pengambilan otomatis kembali ke Belum Diambil (barang tidak
                // mungkin sudah diambil kalau pengerjaan belum selesai).
                if (tempPengerjaan != 'selesai') tempPengambilan = 'belum_diambil';
              }),
            ),
            const SizedBox(height: 16),
            const Text('Status Pengambilan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              tempPengerjaan == 'selesai' ? 'Bisa diubah karena pengerjaan sudah Selesai' : 'Hanya bisa diubah jika pengerjaan sudah Selesai',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: tempPengambilan,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'belum_diambil', child: Text('Belum Diambil')),
                DropdownMenuItem(value: 'sudah_diambil', child: Text('Sudah Diambil')),
              ],
              onChanged: tempPengerjaan == 'selesai' ? (v) => setDialogState(() => tempPengambilan = v ?? tempPengambilan) : null,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );

    if (hasil == true) {
      await DatabaseHelper.instance.updateStatusPengerjaan(widget.orderId, tempPengerjaan);
      await DatabaseHelper.instance.updateStatusPengambilan(widget.orderId, tempPengambilan);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status diperbarui')));
    }
  }

  Future<void> _tambahPembayaran() async {
    if (sisa <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaksi ini sudah Lunas')));
      return;
    }
    final nominalC = TextEditingController();
    final catatanC = TextEditingController();
    String kasJenis = 'kas';

    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tambah Pembayaran'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sisa tagihan: ${formatRupiah(sisa)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: nominalC,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              decoration: const InputDecoration(labelText: 'Nominal Dibayar', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: kasJenis,
              decoration: const InputDecoration(labelText: 'Masuk ke Kas', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'kas', child: Text('KAS Umum')),
                DropdownMenuItem(value: 'vapor', child: Text('KAS Vapor')),
                DropdownMenuItem(value: 'alat', child: Text('KAS Maintenance')),
              ],
              onChanged: (v) => setDialogState(() => kasJenis = v ?? 'kas'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: catatanC,
              decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder(), isDense: true),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );

    if (hasil == true) {
      final nominal = parseRupiah(nominalC.text);
      if (nominal <= 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nominal harus lebih dari 0')));
        return;
      }
      await DatabaseHelper.instance.tambahPembayaran(
        transaksiId: widget.orderId,
        nominal: nominal,
        tanggal: DateTime.now().toIso8601String().substring(0, 10),
        catatan: catatanC.text.trim(),
        kasJenis: kasJenis,
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran tersimpan')));
    }
  }

  void _bagikan() {
    final d = data;
    if (d == null) return;
    final items = (d['items'] as List).cast<Map<String, dynamic>>();
    final buffer = StringBuffer();
    buffer.writeln('*${d['no_transaksi'] ?? '-'}* - WTN Blasting');
    buffer.writeln('Pelanggan: ${d['asal'] ?? '-'}');
    buffer.writeln('Type: ${d['motor'] ?? '-'}');
    buffer.writeln('Proses: ${d['proses'] ?? '-'}');
    buffer.writeln('');
    buffer.writeln('Daftar Barang:');
    for (final it in items) {
      final qty = (it['qty'] as num?)?.toDouble() ?? 1;
      final qtyLabel = qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
      buffer.writeln('- ${it['barang'] ?? '-'} ($qtyLabel x ${formatRupiah(it['harga_satuan'])}) = ${formatRupiah(it['harga'])}');
    }
    buffer.writeln('');
    buffer.writeln('Total: ${formatRupiah(totalHarga)}');
    buffer.writeln('Dibayar: ${formatRupiah(totalDibayar)}');
    buffer.writeln('Sisa: ${formatRupiah(sisa)}');
    buffer.writeln('Status Pembayaran: ${AppColors.bayarLabel(statusPembayaran)}');
    buffer.writeln('Status Pengerjaan: ${AppColors.statusLabel(statusPengerjaan)}');
    buffer.writeln('Status Pengambilan: ${AppColors.ambilLabel(statusPengambilan)}');
    if ((d['catatan'] as String?)?.isNotEmpty == true) {
      buffer.writeln('');
      buffer.writeln('Catatan: ${d['catatan']}');
    }
    final teks = buffer.toString();

    // Ditampilkan sebagai dialog + tombol Salin (bukan lewat plugin share
    // eksternal), supaya tidak menambah dependency native/Kotlin baru ke
    // project — cukup tempel (paste) hasil salinan ke WhatsApp/aplikasi lain.
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cetak / Bagikan'),
        content: SingleChildScrollView(child: SelectableText(teks)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: teks));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disalin ke clipboard')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Salin'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final d = data;
    if (d == null) return const Scaffold(body: Center(child: Text('Transaksi tidak ditemukan')));

    final items = (d['items'] as List).cast<Map<String, dynamic>>();
    final pembayaranList = (d['pembayaran'] as List).cast<Map<String, dynamic>>();
    final tanggal = DateTime.tryParse(d['tanggal'] ?? '');

    return Scaffold(
      appBar: AppBar(title: Text('#${d['no_transaksi'] ?? '-'}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card('Informasi', [
              _baris('Pelanggan', d['asal']),
              _baris('Type Motor', d['motor']),
              _baris('Proses', d['proses']),
              _baris('Tanggal', tanggal != null ? '${tanggal.day} ${bulanNama[tanggal.month]} ${tanggal.year}' : d['tanggal']),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _chip('Pengerjaan', AppColors.statusLabel(statusPengerjaan), AppColors.statusBg(statusPengerjaan), AppColors.statusText(statusPengerjaan)),
              const SizedBox(width: 8),
              _chip('Pengambilan', AppColors.ambilLabel(statusPengambilan), AppColors.ambilBg(statusPengambilan), AppColors.ambilText(statusPengambilan)),
              const SizedBox(width: 8),
              _chip('Pembayaran', AppColors.bayarLabel(statusPembayaran), AppColors.bayarBg(statusPembayaran), AppColors.bayarText(statusPembayaran)),
            ]),
            const SizedBox(height: 16),
            const Text('Daftar Barang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...items.map((it) {
              final qty = (it['qty'] as num?)?.toDouble() ?? 1;
              final qtyLabel = qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
              return Card(
                child: ListTile(
                  dense: true,
                  title: Text(it['barang'] ?? '-'),
                  subtitle: Text('$qtyLabel pcs x ${formatRupiah(it['harga_satuan'])}'),
                  trailing: Text(formatRupiah(it['harga']), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              );
            }),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.biruTerang.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(formatRupiah(totalHarga), style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.biruTua, fontSize: 16)),
              ]),
            ),
            const SizedBox(height: 20),
            const Text('Pembayaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            _card('', [
              _baris('Total Tagihan', formatRupiah(totalHarga)),
              _baris('Sudah Dibayar', formatRupiah(totalDibayar)),
              _baris('Sisa', formatRupiah(sisa)),
            ]),
            const SizedBox(height: 10),
            if (pembayaranList.isNotEmpty) ...[
              const Text('Histori Pembayaran', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              ...pembayaranList.map((p) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.arrow_downward, color: Colors.green, size: 18),
                      title: Text(formatRupiah(p['nominal']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${p['tanggal']} • ${(p['catatan'] as String?)?.isNotEmpty == true ? p['catatan'] : 'Kas ${p['kas_jenis']}'}'),
                    ),
                  )),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _tambahPembayaran,
              icon: const Icon(Icons.add),
              label: const Text('Tambah Pembayaran'),
            ),
            if ((d['catatan'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 20),
              const Text('Catatan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              Text(d['catatan']),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderFormPage(orderId: widget.orderId)));
                    _load();
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(onPressed: _ubahStatus, icon: const Icon(Icons.sync_alt), label: const Text('Ubah Status')),
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _bagikan,
                style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua),
                icon: const Icon(Icons.share),
                label: const Text('Cetak / Bagikan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) ...[
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
        ],
        ...children,
      ]),
    );
  }

  Widget _baris(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
        Expanded(child: Text('${value ?? '-'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _chip(String label, String value, Color bg, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(label, style: TextStyle(fontSize: 9, color: fg.withOpacity(0.8))),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
