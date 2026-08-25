import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'database_helper.dart';

// http.Client custom yang menyisipkan header otorisasi dari google_sign_in
// ke setiap request, supaya bisa dipakai langsung oleh package googleapis.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

class BackupService {
  static final BackupService instance = BackupService._internal();
  BackupService._internal();

  // Scope 'drive.file': aplikasi hanya bisa mengakses file yang DIBUAT oleh
  // aplikasi ini sendiri di Drive milik user, bukan seluruh isi Drive-nya.
  // Ini scope paling aman untuk kebutuhan backup seperti ini.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/drive.file'],
  );

  GoogleSignInAccount? currentUser;

  static const _namaFolder = 'WTN Blasting Backup';
  static const _namaFileBackup = 'wtn_blasting_backup.db';

  Future<GoogleSignInAccount?> signIn() async {
    currentUser = await _googleSignIn.signIn();
    return currentUser;
  }

  // Coba login otomatis pakai sesi sebelumnya (tanpa munculkan dialog akun),
  // dipanggil saat app dibuka supaya user tidak perlu login berulang kali.
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      currentUser = await _googleSignIn.signInSilently();
    } catch (_) {
      currentUser = null;
    }
    return currentUser;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    currentUser = null;
  }

  Future<drive.DriveApi> _driveApi() async {
    if (currentUser == null) {
      throw Exception('Belum login akun Google');
    }
    final headers = await currentUser!.authHeaders;
    final client = _GoogleAuthClient(headers);
    return drive.DriveApi(client);
  }

  Future<String> _dbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'wtn_blasting.db');
  }

  Future<String> _cariAtauBuatFolder(drive.DriveApi api) async {
    final hasil = await api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' and name='$_namaFolder' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );
    if (hasil.files != null && hasil.files!.isNotEmpty) {
      return hasil.files!.first.id!;
    }
    final folderBaru = drive.File()
      ..name = _namaFolder
      ..mimeType = 'application/vnd.google-apps.folder';
    final dibuat = await api.files.create(folderBaru);
    return dibuat.id!;
  }

  Future<String?> _cariFileBackup(drive.DriveApi api, String folderId) async {
    final hasil = await api.files.list(
      q: "'$folderId' in parents and name='$_namaFileBackup' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id, modifiedTime)',
    );
    if (hasil.files != null && hasil.files!.isNotEmpty) {
      return hasil.files!.first.id;
    }
    return null;
  }

  // Upload (atau timpa jika sudah ada) file database ke folder khusus di
  // Google Drive milik user yang sedang login.
  Future<void> backupSekarang() async {
    final api = await _driveApi();
    final folderId = await _cariAtauBuatFolder(api);
    final fileIdLama = await _cariFileBackup(api, folderId);

    final path = await _dbPath();
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('File database tidak ditemukan di perangkat');
    }

    final media = drive.Media(file.openRead(), await file.length());

    if (fileIdLama != null) {
      await api.files.update(drive.File(), fileIdLama, uploadMedia: media);
    } else {
      final metadata = drive.File()
        ..name = _namaFileBackup
        ..parents = [folderId];
      await api.files.create(metadata, uploadMedia: media);
    }

    await DatabaseHelper.instance.setPengaturan('backup_terakhir', DateTime.now().toIso8601String());
  }

  // Download backup terbaru dari Drive dan menimpa database lokal.
  // Setelah ini koneksi database ditutup supaya file yang baru dibaca ulang.
  Future<void> restoreDariDrive() async {
    final api = await _driveApi();
    final folderId = await _cariAtauBuatFolder(api);
    final fileId = await _cariFileBackup(api, folderId);
    if (fileId == null) {
      throw Exception('Belum ada file backup di Google Drive');
    }

    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final path = await _dbPath();
    final file = File(path);
    final sink = file.openWrite();
    await media.stream.pipe(sink);
    await sink.close();

    await DatabaseHelper.instance.tutupDatabase();
  }

  Future<String?> getBackupTerakhir() async {
    final v = await DatabaseHelper.instance.getPengaturan('backup_terakhir');
    return v.isEmpty ? null : v;
  }

  Future<bool> getAutoBackupEnabled() async {
    final v = await DatabaseHelper.instance.getPengaturan('auto_backup_enabled', defaultValue: 'false');
    return v == 'true';
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    await DatabaseHelper.instance.setPengaturan('auto_backup_enabled', enabled.toString());
  }

  // Dipanggil sekali tiap app dibuka (lihat main.dart). Kalau auto-backup
  // aktif, user sudah pernah login, dan backup terakhir lebih dari 24 jam
  // lalu (atau belum pernah), lakukan backup diam-diam di background.
  // Kegagalan (mis. tidak ada internet) dibiarkan saja, dicoba lagi nanti.
  Future<void> cekAutoBackup() async {
    final aktif = await getAutoBackupEnabled();
    if (!aktif) return;

    await signInSilently();
    if (currentUser == null) return;

    final terakhirStr = await getBackupTerakhir();
    if (terakhirStr != null) {
      final terakhir = DateTime.tryParse(terakhirStr);
      if (terakhir != null && DateTime.now().difference(terakhir).inHours < 24) {
        return;
      }
    }

    try {
      await backupSekarang();
    } catch (_) {
      // diamkan, dicoba lagi di sesi berikutnya
    }
  }
}
