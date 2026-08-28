import 'package:flutter/material.dart';
import '../database_helper.dart';
import 'order_form_page.dart';
import 'kas_keluar_page.dart';
import 'backup_page.dart';
import 'laporan_page.dart';
import 'audit_log_page.dart';
import 'export_page.dart';

class LainnyaPage extends StatefulWidget {
  const LainnyaPage({super.key});
  @override
  State<LainnyaPage> createState() => _LainnyaPageState();
}

class _LainnyaPageState extends State<LainnyaPage> {
  String tipeGrafik = 'garis';

  @override
  void initState() {
    super.initState();
    _loadTipeGrafik();
  }

  Future<void> _loadTipeGrafik() async {
    final v = await DatabaseHelper.instance.getPengaturan('grafik_omset_tipe', defaultValue: 'garis');
    setState(() => tipeGrafik = v);
  }

  Future<void> _pilihTipeGrafik() async {
    final hasil = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tampilan Grafik Omset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: 'garis',
              groupValue: tipeGrafik,
              title: const Text('Grafik Garis'),
              subtitle: const Text('Naik turun (line chart)'),
              onChanged: (v) => Navigator.pop(context, v),
            ),
            RadioListTile<String>(
              value: 'batang',
              groupValue: tipeGrafik,
              title: const Text('Grafik Batang'),
              subtitle: const Text('Bar chart'),
              onChanged: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ],
      ),
    );
    if (hasil != null && hasil != tipeGrafik) {
      await DatabaseHelper.instance.setPengaturan('grafik_omset_tipe', hasil);
      setState(() => tipeGrafik = hasil);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tampilan grafik omset diperbarui')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: ListView(
        children: [
          ListTile(leading: const Icon(Icons.payments), title: const Text('Pengeluaran'), subtitle: const Text('Pemasukan, pengeluaran, saldo'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KasKeluarPage()))),
          const Divider(),
          ListTile(leading: const Icon(Icons.summarize), title: const Text('Laporan Keuangan'), subtitle: const Text('Pemasukan, pengeluaran, laba bersih'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LaporanKeuanganPage()))),
          ListTile(leading: const Icon(Icons.assignment), title: const Text('Laporan Transaksi'), subtitle: const Text('Rekap status & jumlah transaksi'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LaporanTransaksiPage()))),
          ListTile(leading: const Icon(Icons.ios_share), title: const Text('Export Laporan'), subtitle: const Text('Export ke PDF / Excel'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportLaporanPage()))),
          const Divider(),
          ListTile(leading: const Icon(Icons.cloud_upload), title: const Text('Backup ke Google Drive'), subtitle: const Text('Sinkron database ke akun Google kamu'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage()))),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.show_chart),
            title: const Text('Tampilan Grafik Omset'),
            subtitle: Text(tipeGrafik == 'batang' ? 'Grafik Batang' : 'Grafik Garis'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pilihTipeGrafik,
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.two_wheeler), title: const Text('Kelola Type Motor'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterDataEditorPage(table: 'master_motor', title: 'Type Motor')))),
          ListTile(leading: const Icon(Icons.palette), title: const Text('Kelola Warna Cat'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterDataEditorPage(table: 'master_warna_cat', title: 'Warna Cat')))),
          ListTile(leading: const Icon(Icons.brush), title: const Text('Kelola Warna Lis'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterDataEditorPage(table: 'master_warna_lis', title: 'Warna Lis')))),
          ListTile(leading: const Icon(Icons.build), title: const Text('Kelola Jenis Proses'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterDataEditorPage(table: 'master_proses', title: 'Jenis Proses')))),
          const Divider(),
          ListTile(leading: const Icon(Icons.history_edu), title: const Text('Riwayat Aktivitas'), subtitle: const Text('Audit log semua aksi penting'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditLogPage()))),
        ],
      ),
    );
  }
}