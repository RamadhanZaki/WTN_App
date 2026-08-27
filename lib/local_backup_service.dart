import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'database_helper.dart';

class LocalBackupService {
  static final LocalBackupService instance = LocalBackupService._internal();
  LocalBackupService._internal();

  Future<String> _dbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'wtn_blasting.db');
  }

  // Membuka menu "Bagikan" bawaan sistem (Simpan ke Files, kirim lewat
  // WhatsApp/Email/Bluetooth/Drive, dll) berisi salinan file database saat
  // ini. Tidak butuh izin penyimpanan khusus karena memakai mekanisme share
  // resmi Android/iOS.
  Future<void> exportViaShare() async {
    final path = await _dbPath();
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Database tidak ditemukan di perangkat');
    }

    final tanggal = DateTime.now().toIso8601String().substring(0, 10);
    final namaFile = 'wtn_blasting_backup_$tanggal.db';

    // Salin dulu ke folder temporary dengan nama yang jelas (mengandung
    // tanggal) supaya user tidak bingung saat menyimpan/mengirim filenya —
    // file asli di documents directory tidak disentuh.
    final tempDir = await getTemporaryDirectory();
    final tempFile = await file.copy(p.join(tempDir.path, namaFile));

    await Share.shareXFiles(
      [XFile(tempFile.path)],
      text: 'Backup database WTN Blasting - $tanggal',
      subject: namaFile,
    );
  }

  // Membuka file picker sistem supaya user memilih file .db dari
  // penyimpanan HP (Downloads, Google Drive lokal, dll), memvalidasi bahwa
  // itu benar file SQLite, lalu menimpa database aplikasi dengan file itu.
  Future<void> importDariFile() async {
    final hasil = await FilePicker.platform.pickFiles(type: FileType.any);
    if (hasil == null || hasil.files.isEmpty || hasil.files.first.path == null) {
      throw Exception('Tidak ada file yang dipilih');
    }

    final sumberFile = File(hasil.files.first.path!);
    if (!await sumberFile.exists()) {
      throw Exception('File tidak ditemukan');
    }

    // Validasi: cek 16 byte pertama file harus header standar SQLite
    // ("SQLite format 3\u0000"), supaya tidak menimpa database dengan file
    // yang salah/rusak.
    final raf = await sumberFile.open();
    final header = await raf.read(16);
    await raf.close();
    final headerStr = String.fromCharCodes(header);
    if (!headerStr.startsWith('SQLite format 3')) {
      throw Exception('File yang dipilih bukan database yang valid');
    }

    // Safety net: sebelum database saat ini ditimpa, simpan dulu salinannya
    // (diam-diam, 1 slot tetap — bukan riwayat tak terbatas) supaya kalau
    // ternyata salah pilih file, database sebelum import masih bisa
    // dipulihkan lewat pemulihanSebelumImport().
    final tujuanPath = await _dbPath();
    final fileSaatIni = File(tujuanPath);
    if (await fileSaatIni.exists()) {
      final dir = await getApplicationDocumentsDirectory();
      await fileSaatIni.copy(p.join(dir.path, _namaSafetyBackup));
    }

    await DatabaseHelper.instance.tutupDatabase();
    await sumberFile.copy(tujuanPath);
  }

  static const _namaSafetyBackup = 'wtn_blasting_sebelum_import.db';

  Future<bool> adaSafetyBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _namaSafetyBackup)).exists();
  }

  // Mengembalikan database ke kondisi tepat SEBELUM import terakhir
  // dilakukan (pakai salinan safety net di atas). Dipakai kalau user
  // ternyata salah pilih file saat import.
  Future<void> pulihkanSebelumImport() async {
    final dir = await getApplicationDocumentsDirectory();
    final safetyFile = File(p.join(dir.path, _namaSafetyBackup));
    if (!await safetyFile.exists()) {
      throw Exception('Tidak ada backup otomatis sebelum-import yang tersimpan');
    }
    final tujuanPath = await _dbPath();
    await DatabaseHelper.instance.tutupDatabase();
    await safetyFile.copy(tujuanPath);
  }
}
