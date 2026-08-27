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
enum _PeriodeCepat { hariIni, mingguIni, bulanIni, tahunIni, custom }

class ExportLaporanPage extends StatefulWidget {
  const ExportLaporanPage({super.key});
  @override
  State<ExportLaporanPage> createState() => _ExportLaporanPageState();
}

class _ExportLaporanPageState extends State<ExportLaporanPage> {
  _JenisLaporan jenis = _JenisLaporan.transaksi;
  _FormatExport format = _FormatExport.pdf;
  _PeriodeCepat periode = _PeriodeCepat.bulanIni;
  DateTimeRange? customRange;
  bool memproses = false;

  (DateTime, DateTime) _rentang() {
    final now = DateTime.now();
    switch (periode) {
      case _PeriodeCepat.hariIni:
        return (DateTime(now.year, now.month, now.day), now);
      case _PeriodeCepat.mingguIni:
        final awal = now.subtract(Duration(days: now.weekday - 1));
        return (DateTime(awal.year, awal.month, awal.day), now);
      case _PeriodeCepat.bulanIni:
        return (DateTime(now.year, now.month, 1), now);
      case _PeriodeCepat.tahunIni:
        return (DateTime(now.year, 1, 1), now);
      case _PeriodeCepat.custom:
        return customRange != null ? (customRange!.start, customRange!.end) : (DateTime(now.year, now.month, 1), now);
    }
  }

  String _labelPeriode(_PeriodeCepat f) {
    switch (f) {
      case _PeriodeCepat.hariIni: return 'Hari Ini';
      case _PeriodeCepat.mingguIni: return 'Minggu Ini';
      case _PeriodeCepat.bulanIni: return 'Bulan Ini';
      case _PeriodeCepat.tahunIni: return 'Tahun Ini';
      case _PeriodeCepat.custom: return 'Custom';
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

  Future<void> _pilihCustomRange() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: customRange);
    if (r != null) setState(() { customRange = r; periode = _PeriodeCepat.custom; });
  }

  String _fmtTanggal(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<List<List<String>>> _ambilBaris() async {
    final (mulai, selesai) = _rentang();
    switch (jenis) {
      case _JenisLaporan.transaksi:
        final list = await DatabaseHelper.instance.cariTransaksi(tanggalMulai: mulai, tanggalSelesai: selesai);
        final rows = <List<String>>[
          ['No Transaksi', 'Tanggal', 'Pelanggan', 'Motor', 'Proses', 'Total', 'Status', 'Pengambilan', 'Pembayaran'],
        ];
        for (final t in list) {
          rows.add([
            '${t['no_transaksi'] ?? '-'}',
            '${t['tanggal'] ?? '-'}',
            '${t['asal'] ?? '-'}',
            '${t['motor'] ?? '-'}',
            '${t['proses'] ?? '-'}',
            formatRupiah(t['total_harga']),
            AppColors.statusLabel((t['status'] ?? 'pending') as String),
            AppColors.ambilLabel((t['status_pengambilan'] ?? 'belum_diambil') as String),
            AppColors.bayarLabel((t['status_pembayaran'] ?? 'belum_bayar') as String),
          ]);
        }
        return rows;
      case _JenisLaporan.pemasukan:
        final list = await DatabaseHelper.instance.cariTransaksi(tanggalMulai: mulai, tanggalSelesai: selesai);
        final rows = <List<String>>[
          ['No Transaksi', 'Tanggal', 'Pelanggan', 'Total Tagihan', 'Sudah Dibayar', 'Status'],
        ];
        for (final t in list) {
          rows.add([
            '${t['no_transaksi'] ?? '-'}',
            '${t['tanggal'] ?? '-'}',
            '${t['asal'] ?? '-'}',
            formatRupiah(t['total_harga']),
            formatRupiah(t['total_dibayar'] ?? 0),
            AppColors.bayarLabel((t['status_pembayaran'] ?? 'belum_bayar') as String),
          ]);
        }
        return rows;
      case _JenisLaporan.pengeluaran:
        final list = await DatabaseHelper.instance.getPengeluaranByBulan(mulai.month, mulai.year, tanggalMulai: mulai, tanggalSelesai: selesai);
        final rows = <List<String>>[
          ['Tanggal', 'Sumber Kas', 'Nominal', 'Catatan'],
        ];
        for (final r in list) {
          rows.add(['${r['tanggal']}', '${r['sumber']}', formatRupiah(r['nominal']), '${r['catatan'] ?? '-'}']);
        }
        return rows;
      case _JenisLaporan.labaRugi:
        final data = await DatabaseHelper.instance.getLaporanKeuangan(mulai: mulai, selesai: selesai);
        return [
          ['Keterangan', 'Nominal'],
          ['Total Pemasukan', formatRupiah(data['pemasukan'])],
          ['Total Pengeluaran', formatRupiah(data['pengeluaran'])],
          ['Laba Bersih', formatRupiah(data['laba_bersih'])],
          ['Saldo (Semua Kas)', formatRupiah(data['saldo'])],
          ['Piutang', formatRupiah(data['piutang'])],
        ];
    }
  }

  Future<void> _export() async {
    setState(() => memproses = true);
    try {
      final rows = await _ambilBaris();
      final (mulai, selesai) = _rentang();
      final judul = _labelJenis(jenis);
      final periodeTeks = '${_fmtTanggal(mulai)} - ${_fmtTanggal(selesai)}';
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
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: rows.first,
                data: rows.skip(1).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
                border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
              ),
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
        sheet.appendRow([]);
        for (final row in rows) {
          sheet.appendRow(row.map((v) => xl.TextCellValue(v)).toList());
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
                onSelected: (_) => setState(() => jenis = j),
                selectedColor: AppColors.biruTua,
                labelStyle: TextStyle(color: jenis == j ? Colors.white : Colors.black87, fontSize: 12),
              ),
          ]),
          const SizedBox(height: 20),
          const Text('Periode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in [_PeriodeCepat.hariIni, _PeriodeCepat.mingguIni, _PeriodeCepat.bulanIni, _PeriodeCepat.tahunIni])
              ChoiceChip(
                label: Text(_labelPeriode(f)),
                selected: periode == f,
                onSelected: (_) => setState(() => periode = f),
                selectedColor: AppColors.biruTua,
                labelStyle: TextStyle(color: periode == f ? Colors.white : Colors.black87, fontSize: 12),
              ),
            ActionChip(
              label: Text(periode == _PeriodeCepat.custom && customRange != null ? '${_fmtTanggal(customRange!.start)} - ${_fmtTanggal(customRange!.end)}' : 'Custom Tanggal'),
              avatar: const Icon(Icons.date_range, size: 16),
              backgroundColor: periode == _PeriodeCepat.custom ? AppColors.biruTua.withOpacity(0.15) : null,
              onPressed: _pilihCustomRange,
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
