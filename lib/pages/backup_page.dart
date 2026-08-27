import 'package:flutter/material.dart';
import '../backup_service.dart';
import '../local_backup_service.dart';
import '../database_helper.dart';
import '../app_theme.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool loading = true;
  bool processing = false;
  bool autoBackup = false;
  String? emailAkun;
  String? backupTerakhir;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => loading = true);
    final akun = await BackupService.instance.signInSilently();
    final auto = await BackupService.instance.getAutoBackupEnabled();
    final terakhir = await BackupService.instance.getBackupTerakhir();
    setState(() {
      emailAkun = akun?.email;
      autoBackup = auto;
      backupTerakhir = terakhir;
      loading = false;
    });
  }

  Future<void> _login() async {
    setState(() => processing = true);
    try {
      final akun = await BackupService.instance.signIn();
      setState(() => emailAkun = akun?.email);
      if (akun == null) _pesan('Login dibatalkan');
    } catch (e) {
      _pesan('Gagal login: $e');
    }
    setState(() => processing = false);
  }

  Future<void> _logout() async {
    await BackupService.instance.signOut();
    setState(() {
      emailAkun = null;
      autoBackup = false;
    });
    await BackupService.instance.setAutoBackupEnabled(false);
  }

  Future<void> _backupSekarang() async {
    setState(() => processing = true);
    try {
      await BackupService.instance.backupSekarang();
      final terakhir = await BackupService.instance.getBackupTerakhir();
      setState(() => backupTerakhir = terakhir);
      await DatabaseHelper.instance.catatRiwayatBackup(tipe: 'manual', status: 'berhasil');
      _pesan('Backup berhasil disimpan ke Google Drive');
    } catch (e) {
      await DatabaseHelper.instance.catatRiwayatBackup(tipe: 'manual', status: 'gagal', keterangan: '$e');
      _pesan('Backup gagal: $e');
    }
    setState(() => processing = false);
  }

  Future<void> _restore() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Database'),
        content: const Text(
          'Data yang ada di HP saat ini akan digantikan sepenuhnya dengan backup terakhir dari Google Drive. Tindakan ini tidak bisa dibatalkan. Lanjutkan?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Restore'),
          ),
        ],
      ),
    );
    if (konfirmasi != true) return;

    setState(() => processing = true);
    try {
      await BackupService.instance.restoreDariDrive();
      await DatabaseHelper.instance.catatRiwayatBackup(tipe: 'restore', status: 'berhasil');
      _pesan('Restore berhasil. Silakan tutup dan buka ulang aplikasi.');
    } catch (e) {
      await DatabaseHelper.instance.catatRiwayatBackup(tipe: 'restore', status: 'gagal', keterangan: '$e');
      _pesan('Restore gagal: $e');
    }
    setState(() => processing = false);
  }

  Future<void> _lihatRiwayatBackup() async {
    final list = await DatabaseHelper.instance.getRiwayatBackup();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.9, expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Riwayat Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Belum ada riwayat backup', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        final berhasil = r['status'] == 'berhasil';
                        final tipeLabel = r['tipe'] == 'manual' ? 'Backup Manual' : r['tipe'] == 'otomatis' ? 'Backup Otomatis' : 'Restore';
                        return ListTile(
                          dense: true,
                          leading: Icon(berhasil ? Icons.check_circle : Icons.error, color: berhasil ? Colors.green : Colors.red, size: 20),
                          title: Text(tipeLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('${_formatWaktu(r['waktu'])}${(r['keterangan'] as String?)?.isNotEmpty == true ? '\n${r['keterangan']}' : ''}', style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  // Export database ke file .db lewat menu "Bagikan" bawaan sistem
  // (simpan ke penyimpanan HP, kirim lewat WhatsApp/Email/Drive, dll) —
  // tidak butuh login Google, murni lokal.
  Future<void> _exportLokal() async {
    setState(() => processing = true);
    try {
      await LocalBackupService.instance.exportViaShare();
      _pesan('Database siap dibagikan/disimpan');
    } catch (e) {
      _pesan('Export gagal: $e');
    }
    setState(() => processing = false);
  }

  // Import database dari file .db yang dipilih user lewat file picker
  // sistem, lalu menimpa database aplikasi saat ini.
  Future<void> _importLokal() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Database'),
        content: const Text(
          'Data yang ada di HP saat ini akan digantikan sepenuhnya dengan isi file database yang kamu pilih. Tindakan ini tidak bisa dibatalkan. Lanjutkan?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Import'),
          ),
        ],
      ),
    );
    if (konfirmasi != true) return;

    setState(() => processing = true);
    try {
      await LocalBackupService.instance.importDariFile();
      _pesan('Import berhasil. Silakan tutup dan buka ulang aplikasi.');
    } catch (e) {
      _pesan('Import gagal: $e');
    }
    setState(() => processing = false);
  }

  void _pesan(String teks) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  String _formatWaktu(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${dua(dt.day)}/${dua(dt.month)}/${dt.year} ${dua(dt.hour)}:${dua(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup ke Google Drive'), actions: [
        IconButton(icon: const Icon(Icons.history), tooltip: 'Riwayat Backup', onPressed: _lihatRiwayatBackup),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    CircleAvatar(backgroundColor: AppColors.biruTua, child: const Icon(Icons.account_circle, color: Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(emailAkun ?? 'Belum login', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          emailAkun == null ? 'Login untuk mengaktifkan backup' : 'Terhubung ke Google Drive',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ]),
                    ),
                    if (processing)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      TextButton(
                        onPressed: emailAkun == null ? _login : _logout,
                        child: Text(emailAkun == null ? 'Login' : 'Logout'),
                      ),
                  ]),
                ),
                const SizedBox(height: 20),
                Text(
                  'Backup terakhir: ${backupTerakhir != null ? _formatWaktu(backupTerakhir!) : 'Belum pernah backup'}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (emailAkun == null || processing) ? null : _backupSekarang,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua, padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Backup Sekarang'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: (emailAkun == null || processing) ? null : _restore,
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Restore dari Drive'),
                ),
                const SizedBox(height: 20),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-backup harian'),
                  subtitle: const Text('Backup otomatis tiap kali app dibuka (maksimal 1x per 24 jam)'),
                  value: autoBackup,
                  onChanged: emailAkun == null
                      ? null
                      : (v) async {
                          setState(() => autoBackup = v);
                          await BackupService.instance.setAutoBackupEnabled(v);
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  'Database disimpan di folder "WTN Blasting Backup" pada Google Drive akun kamu.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                const Text('Backup Lokal (Tanpa Google)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  'Simpan atau muat file database langsung dari HP, tidak perlu login Google.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: processing ? null : _exportLokal,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Export Database (Simpan ke HP)'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                  onPressed: processing ? null : _importLokal,
                  icon: const Icon(Icons.file_open),
                  label: const Text('Import Database dari File'),
                ),
              ],
            ),
    );
  }
}
