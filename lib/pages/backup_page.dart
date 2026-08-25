import 'package:flutter/material.dart';
import '../backup_service.dart';
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
      _pesan('Backup berhasil disimpan ke Google Drive');
    } catch (e) {
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
      _pesan('Restore berhasil. Silakan tutup dan buka ulang aplikasi.');
    } catch (e) {
      _pesan('Restore gagal: $e');
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
      appBar: AppBar(title: const Text('Backup ke Google Drive')),
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
              ],
            ),
    );
  }
}
