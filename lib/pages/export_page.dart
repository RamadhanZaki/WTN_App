import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xl;
import '../database_helper.dart';
import '../app_theme.dart';

enum _JenisLaporan { transaksi, pemasukan, pengeluaran, labaRugi }
enum _FormatExport { pdf, excel }
// Hari Ini / Minggu Ini / Bulan Ini / Custom Tanggal dihapus supaya picker
// periode di halaman ini sama seperti Page Laporan Transaksi: cuma "Tahun
// Ini" + "Pilih Bulan" (dialog Bulan & Tahun).
enum _PeriodeCepat { tahunIni, bulanTahun }

class ExportLaporanPage extends StatefulWidget {
  const ExportLaporanPage({super.key});
  @override
  State<ExportLaporanPage> createState() => _ExportLaporanPageState();
}

class _ExportLaporanPageState extends State<ExportLaporanPage> {
  _JenisLaporan jenis = _JenisLaporan.transaksi;
  _FormatExport format = _FormatExport.pdf;
  _PeriodeCepat periode = _PeriodeCepat.bulanTahun;
  bool memproses = false;

  // Sama seperti Page Transaksi & Page Pengeluaran: dropdown Bulan/Tahun di
  // sini HANYA menampilkan periode yang benar-benar ada datanya di database
  // (bukan 12 bulan / rentang tahun tetap), supaya tidak pernah menampilkan
  // bulan/tahun kosong yang tidak sesuai isi database.
  int? bulanPilih;
  int? tahunPilih;
  List<int> tahunTersedia = [DateTime.now().year];
  List<int> bulanTersedia = [DateTime.now().month];
  bool periodeSiap = false;

  final bulanNama = const ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  @override
  void initState() {
    super.initState();
    _muatPeriodeTersedia();
  }

  // Jenis laporan menentukan tabel mana yang jadi sumber periode:
  // - transaksi/pemasukan -> tabel transaksi
  // - pengeluaran -> tabel kas_keluar (baris pengeluaran saja)
  // - labaRugi -> gabungan keduanya, karena laba/rugi butuh pemasukan & pengeluaran
  Future<List<int>> _ambilTahunTersedia() async {
    if (jenis == _JenisLaporan.pengeluaran) {
      return DatabaseHelper.instance.getTahunPengeluaranTersedia();
    } else if (jenis == _JenisLaporan.labaRugi) {
      final a = await DatabaseHelper.instance.getTahunTransaksiTersedia();
      final b = await DatabaseHelper.instance.getTahunPengeluaranTersedia();
      final gabung = {...a, ...b}.toList()..sort((x, y) => y.compareTo(x));
      return gabung;
    }
    return DatabaseHelper.instance.getTahunTransaksiTersedia();
  }

  Future<List<int>> _ambilBulanTersedia(int tahun) async {
    if (jenis == _JenisLaporan.pengeluaran) {
      return DatabaseHelper.instance.getBulanPengeluaranTersedia(tahun);
    } else if (jenis == _JenisLaporan.labaRugi) {
      final a = await DatabaseHelper.instance.getBulanTransaksiTersedia(tahun);
      final b = await DatabaseHelper.instance.getBulanPengeluaranTersedia(tahun);
      final gabung = {...a, ...b}.toList()..sort((x, y) => y.compareTo(x));
      return gabung;
    }
    return DatabaseHelper.instance.getBulanTransaksiTersedia(tahun);
  }

  // Dipanggil saat halaman dibuka & setiap kali Jenis Laporan diganti, karena
  // periode yang tersedia bisa berbeda antara transaksi dan pengeluaran.
  Future<void> _muatPeriodeTersedia() async {
    setState(() => periodeSiap = false);
    final now = DateTime.now();
    final tahunList = await _ambilTahunTersedia();

    if (tahunList.isEmpty) {
      tahunTersedia = [now.year];
      bulanTersedia = [now.month];
      tahunPilih = now.year;
      bulanPilih = now.month;
      periodeSiap = true;
      if (mounted) setState(() {});
      return;
    }

    tahunTersedia = tahunList;
    if (tahunPilih == null || !tahunTersedia.contains(tahunPilih)) tahunPilih = tahunTersedia.first;

    final bulanList = await _ambilBulanTersedia(tahunPilih!);
    bulanTersedia = bulanList.isEmpty ? [now.month] : bulanList;
    if (bulanPilih == null || !bulanTersedia.contains(bulanPilih)) bulanPilih = bulanTersedia.first;

    periodeSiap = true;
    if (mounted) setState(() {});
  }

  (DateTime, DateTime) _rentang() {
    final now = DateTime.now();
    switch (periode) {
      case _PeriodeCepat.tahunIni:
        return (DateTime(now.year, 1, 1), now);
      case _PeriodeCepat.bulanTahun:
        final b = bulanPilih ?? now.month;
        final t = tahunPilih ?? now.year;
        final awal = DateTime(t, b, 1);
        // Rentang satu bulan penuh: tanggal 1 s.d. hari terakhir bulan itu,
        // konsisten dengan pola di Page Laporan Transaksi.
        final akhir = DateTime(t, b + 1, 0);
        return (awal, akhir);
    }
  }

  String _labelJenis(_JenisLaporan j) {
    switch (j) {
      case _JenisLaporan.transaksi: return 'Laporan Transaksi';
      case _JenisLaporan.pemasukan: return 'Laporan Pemasukan';
      case _JenisLaporan.pengeluaran: return 'Laporan Pengeluaran';
      case _JenisLaporan.labaRugi: return 'Laporan Laba/Rugi';
    }
  }

  // Dialog "Pilih Bulan & Tahun" — sama seperti di Page Laporan Transaksi,
  // tapi daftar bulan/tahunnya diambil dari data yang benar-benar ada di
  // database (tahunTersedia/_ambilBulanTersedia), bukan rentang tetap.
  Future<void> _pilihBulanTahun() async {
    final now = DateTime.now();
    int bulanDialog = bulanPilih ?? now.month;
    int tahunDialog = tahunPilih ?? now.year;
    List<int> bulanListDialog = bulanTersedia.isEmpty ? [now.month] : List<int>.from(bulanTersedia);

    final hasil = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Pilih Bulan & Tahun'),
              content: Row(mainAxisSize: MainAxisSize.min, children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Bulan'),
                    value: bulanDialog,
                    items: (List<int>.from(bulanListDialog)..sort()).map((b) => DropdownMenuItem(value: b, child: Text(bulanNama[b]))).toList(),
                    onChanged: (v) => setStateDialog(() => bulanDialog = v ?? bulanDialog),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Tahun'),
                    value: tahunDialog,
                    items: tahunTersedia.map((t) => DropdownMenuItem(value: t, child: Text('$t'))).toList(),
                    onChanged: (v) async {
                      final tahunBaru = v ?? tahunDialog;
                      final bulanBaru = await _ambilBulanTersedia(tahunBaru);
                      setStateDialog(() {
                        tahunDialog = tahunBaru;
                        bulanListDialog = bulanBaru.isEmpty ? [now.month] : bulanBaru;
                        if (!bulanListDialog.contains(bulanDialog)) bulanDialog = bulanListDialog.first;
                      });
                    },
                  ),
                ),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                FilledButton(onPressed: () => Navigator.pop(ctx, (bulanDialog, tahunDialog)), child: const Text('Pilih')),
              ],
            );
          },
        );
      },
    );

    if (hasil != null) {
      setState(() { bulanPilih = hasil.$1; tahunPilih = hasil.$2; periode = _PeriodeCepat.bulanTahun; });
    }
  }

  String _fmtTanggal(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<List<List<String>>> _ambilBaris() async {
    final (mulai, selesai) = _rentang();
    switch (jenis) {
      case _JenisLaporan.transaksi:
        final list = await DatabaseHelper.instance.cariTransaksi(tanggalMulai: mulai, tanggalSelesai: selesai);
        final rows = <List<String>>[
          ['No Transaksi', 'Tanggal', 'Pelanggan', 'Motor', 'Warna Cat', 'Warna Lis', 'Barang', 'Proses', 'Total', 'Sisa Bayar', 'Status', 'Pengambilan', 'Pembayaran', 'Catatan'],
        ];
        double totalSemua = 0;
        for (final t in list) {
          final totalHarga = (t['total_harga'] as num?)?.toDouble() ?? 0;
          final totalDibayar = (t['total_dibayar'] as num?)?.toDouble() ?? 0;
          final sisa = totalHarga > totalDibayar ? totalHarga - totalDibayar : 0;
          totalSemua += totalHarga;
          rows.add([
            '${t['no_transaksi'] ?? '-'}',
            '${t['tanggal'] ?? '-'}',
            '${t['asal'] ?? '-'}',
            '${t['motor'] ?? '-'}',
            '${t['warna_cat'] ?? '-'}',
            '${t['warna_lis'] ?? '-'}',
            '${t['daftar_barang'] ?? '-'}',
            '${t['proses'] ?? '-'}',
            formatRupiah(totalHarga),
            sisa > 0 ? formatRupiah(sisa) : '-',
            AppColors.statusLabel((t['status'] ?? 'pending') as String),
            AppColors.ambilLabel((t['status_pengambilan'] ?? 'belum_diambil') as String),
            AppColors.bayarLabel((t['status_pembayaran'] ?? 'belum_bayar') as String),
            '${t['catatan'] ?? '-'}',
          ]);
        }
        if (list.isNotEmpty) rows.add(['', '', '', '', '', '', '', 'TOTAL', formatRupiah(totalSemua), '', '', '', '', '']);
        return rows;
      case _JenisLaporan.pemasukan:
        final list = await DatabaseHelper.instance.cariTransaksi(tanggalMulai: mulai, tanggalSelesai: selesai);
        final rows = <List<String>>[
          ['No Transaksi', 'Tanggal', 'Pelanggan', 'Total Tagihan', 'Sudah Dibayar', 'Sisa/Piutang', 'Status'],
        ];
        double totalTagihan = 0, totalBayar = 0, totalSisa = 0;
        for (final t in list) {
          final th = (t['total_harga'] as num?)?.toDouble() ?? 0;
          final td = (t['total_dibayar'] as num?)?.toDouble() ?? 0;
          final sisa = th > td ? th - td : 0;
          totalTagihan += th;
          totalBayar += td;
          totalSisa += sisa;
          rows.add([
            '${t['no_transaksi'] ?? '-'}',
            '${t['tanggal'] ?? '-'}',
            '${t['asal'] ?? '-'}',
            formatRupiah(th),
            formatRupiah(td),
            sisa > 0 ? formatRupiah(sisa) : '-',
            AppColors.bayarLabel((t['status_pembayaran'] ?? 'belum_bayar') as String),
          ]);
        }
        if (list.isNotEmpty) rows.add(['', 'TOTAL', '', formatRupiah(totalTagihan), formatRupiah(totalBayar), formatRupiah(totalSisa), '']);
        return rows;
      case _JenisLaporan.pengeluaran:
        final list = await DatabaseHelper.instance.getPengeluaranByBulan(mulai.month, mulai.year, tanggalMulai: mulai, tanggalSelesai: selesai);
        final rows = <List<String>>[
          ['Tanggal', 'Sumber Kas', 'Nominal', 'Catatan'],
        ];
        double totalNominal = 0;
        for (final r in list) {
          final nominal = (r['nominal'] as num?)?.toDouble() ?? 0;
          totalNominal += nominal;
          rows.add(['${r['tanggal']}', '${r['sumber']}', formatRupiah(nominal), '${r['catatan'] ?? '-'}']);
        }
        if (list.isNotEmpty) rows.add(['', 'TOTAL', formatRupiah(totalNominal), '']);
        return rows;
      case _JenisLaporan.labaRugi:
        final d = await DatabaseHelper.instance.getLaporanTransaksi(mulai: mulai, selesai: selesai);
        final saldo = await DatabaseHelper.instance.getSaldoTerakhir();
        final rows = <List<String>>[
          ['Keterangan', 'Nominal'],
          ['Total Omset', formatRupiah(d['omzet'])],
          ['Uang Masuk Kas (Pemasukan)', formatRupiah(d['uang_masuk_kas'])],
          ['Total Pengeluaran', formatRupiah(d['pengeluaran'])],
          ['Laba Bersih', formatRupiah(d['laba_bersih'])],
          ['Piutang Belum Tertagih', formatRupiah(d['total_piutang'])],
          ['Saldo Kas', formatRupiah(saldo['kas'])],
          ['Saldo Kas Vapor', formatRupiah(saldo['vapor'])],
          ['Saldo Kas Maintenance', formatRupiah(saldo['alat'])],
          ['Total Saldo (Semua Kas)', formatRupiah((saldo['kas'] ?? 0) + (saldo['vapor'] ?? 0) + (saldo['alat'] ?? 0))],
        ];
        final langgeng = (d['langgeng'] as num?) ?? 0;
        final juki = (d['juki'] as num?) ?? 0;
        final rio = (d['rio'] as num?) ?? 0;
        if (langgeng > 0) rows.add(['Bagian Langgeng', formatRupiah(langgeng)]);
        if (juki > 0) rows.add(['Bagian Juki', formatRupiah(juki)]);
        if (rio > 0) rows.add(['Bagian Rio', formatRupiah(rio)]);
        rows.addAll([
          ['Jumlah Transaksi', '${d['total_transaksi']}'],
          ['  - Selesai', '${d['selesai']}'],
          ['  - Proses', '${d['proses']}'],
          ['  - Antre', '${d['antre']}'],
          ['  - Pending', '${d['pending']}'],
          ['  - Belum Diambil', '${d['belum_diambil']}'],
        ]);
        return rows;
    }
  }

  // Ringkasan tambahan (Total Omset, Uang Masuk Kas, Pengeluaran, Laba
  // Bersih, Pembagian Langgeng/Juki/Rio) ditampilkan untuk semua jenis
  // laporan (bukan cuma Transaksi) supaya gambaran keuangan periode yang
  // sama selalu konsisten di export apa pun yang dipilih.
  Future<List<List<String>>> _ambilRingkasan(DateTime mulai, DateTime selesai) async {
    if (jenis == _JenisLaporan.labaRugi) return []; // sudah jadi tabel utama
    final d = await DatabaseHelper.instance.getLaporanTransaksi(mulai: mulai, selesai: selesai);
    final rows = <List<String>>[
      ['Total Omset', formatRupiah(d['omzet'])],
      ['Uang Masuk Kas', formatRupiah(d['uang_masuk_kas'])],
      ['Pengeluaran', formatRupiah(d['pengeluaran'])],
      ['Laba Bersih', formatRupiah(d['laba_bersih'])],
      ['Piutang Belum Tertagih', formatRupiah(d['total_piutang'])],
    ];
    final langgeng = (d['langgeng'] as num?) ?? 0;
    final juki = (d['juki'] as num?) ?? 0;
    final rio = (d['rio'] as num?) ?? 0;
    if (langgeng > 0) rows.add(['Bagian Langgeng', formatRupiah(langgeng)]);
    if (juki > 0) rows.add(['Bagian Juki', formatRupiah(juki)]);
    if (rio > 0) rows.add(['Bagian Rio', formatRupiah(rio)]);
    return rows;
  }

  Future<void> _export() async {
    setState(() => memproses = true);
    try {
      final rows = await _ambilBaris();
      final (mulai, selesai) = _rentang();
      final ringkasan = await _ambilRingkasan(mulai, selesai);
      final judul = _labelJenis(jenis);
      final periodeTeks = '${_fmtTanggal(mulai)} - ${_fmtTanggal(selesai)}';
      final now = DateTime.now();
      final dicetakTeks = '${_fmtTanggal(now)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final namaFileDasar = '${jenis.name}_${DateTime.now().millisecondsSinceEpoch}';

      final tempDir = await getTemporaryDirectory();
      late File file;

      if (format == _FormatExport.pdf) {
        final doc = pw.Document();
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape,
            build: (ctx) => [
              pw.Text('WTN Blasting - $judul', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Periode: $periodeTeks', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Dicetak: $dicetakTeks', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: rows.first,
                data: rows.skip(1).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                cellStyle: const pw.TextStyle(fontSize: 7),
                cellAlignment: pw.Alignment.centerLeft,
                border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
              ),
              if (ringkasan.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text('Ringkasan', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 6),
                pw.TableHelper.fromTextArray(
                  headers: const ['Keterangan', 'Nominal'],
                  data: ringkasan,
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  cellAlignment: pw.Alignment.centerLeft,
                  border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
                  columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
                ),
              ],
            ],
          ),
        );
        file = File(p.join(tempDir.path, '$namaFileDasar.pdf'));
        await file.writeAsBytes(await doc.save());
      } else {
        final workbook = xl.Excel.createExcel();
        final sheet = workbook['Laporan'];
        sheet.appendRow([xl.TextCellValue('WTN Blasting - $judul')]);
        sheet.appendRow([xl.TextCellValue('Periode: $periodeTeks')]);
        sheet.appendRow([xl.TextCellValue('Dicetak: $dicetakTeks')]);
        sheet.appendRow([]);
        for (final row in rows) {
          sheet.appendRow(row.map((v) => xl.TextCellValue(v)).toList());
        }
        if (ringkasan.isNotEmpty) {
          sheet.appendRow([]);
          sheet.appendRow([xl.TextCellValue('Ringkasan')]);
          for (final row in ringkasan) {
            sheet.appendRow(row.map((v) => xl.TextCellValue(v)).toList());
          }
        }
        workbook.delete('Sheet1');
        file = File(p.join(tempDir.path, '$namaFileDasar.xlsx'));
        final bytes = workbook.encode();
        if (bytes == null) throw Exception('Gagal membuat file Excel');
        await file.writeAsBytes(bytes);
      }

      await Share.shareXFiles([XFile(file.path)], text: '$judul - $periodeTeks');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File laporan siap dibagikan/disimpan')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export gagal: $e')));
    }
    setState(() => memproses = false);
  }

  @override
  Widget build(BuildContext context) {
    final (mulai, selesai) = _rentang();
    return Scaffold(
      appBar: AppBar(title: const Text('Export Laporan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Jenis Laporan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final j in _JenisLaporan.values)
              ChoiceChip(
                label: Text(_labelJenis(j)),
                selected: jenis == j,
                onSelected: (_) {
                  setState(() => jenis = j);
                  _muatPeriodeTersedia();
                },
                selectedColor: AppColors.biruTua,
                labelStyle: TextStyle(color: jenis == j ? Colors.white : Colors.black87, fontSize: 12),
              ),
          ]),
          const SizedBox(height: 20),
          const Text('Periode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('Tahun Ini'),
              selected: periode == _PeriodeCepat.tahunIni,
              onSelected: (_) => setState(() => periode = _PeriodeCepat.tahunIni),
              selectedColor: AppColors.biruTua,
              labelStyle: TextStyle(color: periode == _PeriodeCepat.tahunIni ? Colors.white : Colors.black87, fontSize: 12),
            ),
            ActionChip(
              label: Text(periode == _PeriodeCepat.bulanTahun && bulanPilih != null && tahunPilih != null
                  ? '${bulanNama[bulanPilih!]} $tahunPilih'
                  : 'Pilih Bulan'),
              avatar: const Icon(Icons.calendar_month, size: 16),
              backgroundColor: periode == _PeriodeCepat.bulanTahun ? AppColors.biruTua.withOpacity(0.15) : null,
              onPressed: periodeSiap ? _pilihBulanTahun : null,
            ),
          ]),
          const SizedBox(height: 6),
          Text('Rentang: ${_fmtTanggal(mulai)} - ${_fmtTanggal(selesai)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 20),
          const Text('Format File', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: RadioListTile<_FormatExport>(
                value: _FormatExport.pdf,
                groupValue: format,
                dense: true,
                title: const Text('PDF', style: TextStyle(fontSize: 13)),
                onChanged: (v) => setState(() => format = v!),
              ),
            ),
            Expanded(
              child: RadioListTile<_FormatExport>(
                value: _FormatExport.excel,
                groupValue: format,
                dense: true,
                title: const Text('Excel', style: TextStyle(fontSize: 13)),
                onChanged: (v) => setState(() => format = v!),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: memproses ? null : _export,
            style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua, padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: memproses ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download),
            label: Text(memproses ? 'Memproses...' : 'Export & Bagikan'),
          ),
          const SizedBox(height: 8),
          Text(
            'Data yang diekspor mengikuti jenis laporan & periode yang dipilih di atas.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
