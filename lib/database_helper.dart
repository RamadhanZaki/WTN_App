import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Dipakai setelah restore backup dari Google Drive: menutup koneksi lama
  // supaya panggilan `database` berikutnya membuka ulang file .db yang baru
  // saja ditimpa, bukan memakai koneksi/cache lama.
  Future<void> tutupDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDirectory.path, 'wtn_blasting.db');

    final exists = await File(dbPath).exists();
    if (!exists) {
      final data = await rootBundle.load('assets/wtn_blasting.db');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    final db = await openDatabase(dbPath);
    await _migrasi(db);
    return db;
  }

  // Versi skema saat ini. Naikkan angka ini setiap kali menambah migrasi baru
  // di dalam _migrasi() agar migrasi lama otomatis di-skip pada app yang sudah
  // pernah dibuka sebelumnya.
  static const int _dbVersion = 8;

  Future<void> _migrasi(Database db) async {
    // Skip seluruh proses migrasi kalau versi skema sudah paling baru.
    // Sebelumnya _migrasi() (termasuk PRAGMA table_info, beberapa SELECT
    // COUNT(*), dan CREATE TABLE IF NOT EXISTS) selalu dijalankan ulang
    // setiap kali app dibuka, meski tidak ada perubahan skema yang perlu
    // dilakukan. Ini salah satu penyebab utama loading terasa berat.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pengaturan (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    final versiRow = await db.query('pengaturan', where: 'key = ?', whereArgs: ['db_version']);
    final versiSekarang = versiRow.isNotEmpty ? int.tryParse(versiRow.first['value'] as String? ?? '0') ?? 0 : 0;
    if (versiSekarang >= _dbVersion) return;

    final kolom = await db.rawQuery("PRAGMA table_info(transaksi)");
    final nama = kolom.map((k) => k['name']).toSet();

    Future<void> tambahKolom(String nm, String tipe) async {
      if (!nama.contains(nm)) {
        await db.execute("ALTER TABLE transaksi ADD COLUMN $nm $tipe");
      }
    }

    await tambahKolom('status', "TEXT DEFAULT 'pending'");
    await tambahKolom('no_transaksi', 'TEXT');
    await tambahKolom('proses', 'TEXT');
    await tambahKolom('catatan', 'TEXT');
    await tambahKolom('kas_maintenance', 'REAL');
    await tambahKolom('kas', 'REAL');
    await tambahKolom('kas_vapor', 'REAL');

    if (!nama.contains('status')) {
      await db.execute('''
        UPDATE transaksi SET status = 'selesai'
        WHERE bagian_langgeng IS NOT NULL AND bagian_langgeng != '' AND bagian_langgeng != '-'
      ''');
    }

    if (!nama.contains('no_transaksi')) {
      final rows = await db.query('transaksi', orderBy: 'id ASC');
      for (var i = 0; i < rows.length; i++) {
        final noTrx = 'TRX-${(i + 1).toString().padLeft(5, '0')}';
        await db.update('transaksi', {'no_transaksi': noTrx}, where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaksi_id INTEGER NOT NULL,
        barang TEXT,
        kode TEXT,
        warna_cat TEXT,
        warna_lis TEXT,
        harga REAL
      )
    ''');

    final adaMigrasiItem = await db.rawQuery("SELECT COUNT(*) as c FROM order_items");
    if ((adaMigrasiItem.first['c'] as int) == 0) {
      final rowsLama = await db.query('transaksi');
      for (final r in rowsLama) {
        if (r['barang'] != null && r['barang'].toString().isNotEmpty) {
          await db.insert('order_items', {
            'transaksi_id': r['id'],
            'barang': r['barang'],
            'warna_cat': r['warna_cat'],
            'warna_lis': r['warna_lis'],
            'harga': r['harga'],
          });
        }
      }
    }

    // v3: tambah Qty & Harga Satuan per barang di order_items.
    // PENTING: kolom 'harga' TIDAK diubah maknanya — tetap berisi SUBTOTAL
    // per item (qty x harga_satuan), persis seperti sebelumnya. Ini supaya
    // semua query SUM(harga) yang sudah ada (dashboard, laporan, riwayat
    // transaksi, grafik omset) tetap benar tanpa perlu diubah sama sekali.
    final kolomItem = await db.rawQuery("PRAGMA table_info(order_items)");
    final namaKolomItem = kolomItem.map((k) => k['name']).toSet();

    if (!namaKolomItem.contains('qty')) {
      await db.execute("ALTER TABLE order_items ADD COLUMN qty REAL DEFAULT 1");
    }
    if (!namaKolomItem.contains('harga_satuan')) {
      await db.execute("ALTER TABLE order_items ADD COLUMN harga_satuan REAL");
      // Backfill data lama: qty dianggap 1, jadi harga_satuan = harga (subtotal lama).
      await db.execute("UPDATE order_items SET harga_satuan = harga WHERE harga_satuan IS NULL");
    }

    // v4: 'harga_bahan' TERNYATA berisi catatan pembelian material/bahan habis
    // pakai (bubuk cat, remover, gas, dll), BUKAN katalog nama barang/part
    // motor yang dikerjakan. Itu sebabnya autocomplete di form Tambah Barang
    // salah menyarankan data pembelian bahan. Dibuat tabel BARU khusus katalog
    // barang/part motor, terpisah total dari harga_bahan (yang tidak disentuh
    // sama sekali, tetap ada untuk kebutuhan lain di masa depan).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS katalog_barang (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama_barang TEXT NOT NULL UNIQUE,
        harga_terakhir REAL,
        kategori TEXT,
        satuan TEXT,
        aktif INTEGER DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_katalog_barang_nama ON katalog_barang(nama_barang)');

    final adaKatalog = await db.rawQuery("SELECT COUNT(*) as c FROM katalog_barang");
    if ((adaKatalog.first['c'] as int) == 0) {
      const daftarAwal = [
        'Kop', 'Bak Kopling', 'Cover Kopling', 'Kopling',
        'Bak Kanan', 'Bak Kiri', 'Bak Kanan Kiri',
        'Blok', 'Blok Kop', 'Head', 'Kalter', 'Kalter Set', 'Kalter Blokop',
        'Timing', 'Gear', 'Dinamo', 'CDI', 'Manifold', 'Karbu',
        'Tromol Depan', 'Tromol Belakang', 'Krengkes', 'Footstep', 'Velg',
        'Kaliper', 'Piston', 'Sokbreker', 'Rantai Keteng', 'Pangkon Mesin',
      ];
      for (final nm in daftarAwal) {
        await db.insert('katalog_barang', {'nama_barang': nm}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    for (final t in ['master_motor', 'master_warna_cat', 'master_warna_lis', 'master_proses']) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $t (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nama TEXT NOT NULL
        )
      ''');
    }

    await _seedMasterData(db, 'master_motor', ['Tiger', 'MP', 'KPH', '5TP', 'KLX']);
    await _seedMasterData(db, 'master_warna_cat', ['Hitam Glossy', 'Gun Metal Glossy', 'Bronze Metalik Glossy', 'Hitam Textur']);
    await _seedMasterData(db, 'master_warna_lis', ['Merah', 'Biru', 'Kuning', 'Hijau', 'Putih', 'Pink', 'Ungu', 'Emas', 'Silver', 'Hitam']);
    await _seedMasterData(db, 'master_proses', ['PowderCoating & Vaporblasting', 'Powder Coating', 'Vaporblasting', 'Sandblasting', 'Remove Chrome, PowderCoating, Vaporblasting']);

    // v5: bersihkan data master. Data lama (hasil import Excel) punya banyak
    // variasi Type Motor / Warna Cat / Warna Lis akibat spasi berlebih (mis.
    // 'Tiger' vs 'Tiger '), padahal daftar master hanya diisi beberapa nilai
    // contoh saat pertama kali dibuat. Akibatnya banyak motor/warna asli TIDAK
    // BISA dipilih di dropdown form order. Langkah ini:
    //  1) Merapikan spasi berlebih pada data transaksi lama (isi/nilai TIDAK
    //     diubah, cuma spasi di awal/akhir dihapus — harga, nama pelanggan,
    //     dan seluruh data keuangan sama sekali tidak disentuh).
    //  2) Menambahkan SEMUA varian motor/warna yang pernah benar-benar dipakai
    //     di transaksi ke dalam daftar master, supaya bisa dipilih lagi.
    //     Duplikat yang beda kapitalisasi doang (mis. 'MP' vs 'Mp') tidak
    //     digandakan. Sisa variasi yang mirip (mis. 'GL' vs 'GL 100' vs 'GL
    //     Neotech') sengaja TIDAK ditebak/digabung otomatis oleh sistem —
    //     silakan digabungkan manual lewat menu Kelola di halaman Lainnya
    //     kalau memang dianggap sama, karena pemilik usaha yang paling tahu.
    for (final kolom in ['motor', 'warna_cat', 'warna_lis', 'asal']) {
      await db.rawUpdate('''
        UPDATE transaksi SET $kolom = TRIM($kolom)
        WHERE $kolom IS NOT NULL AND $kolom != TRIM($kolom)
      ''');
    }

    Future<void> gabungkanKeMaster(String table, String kolomTransaksi) async {
      final sudahAda = (await db.query(table)).map((r) => (r['nama'] as String).trim().toLowerCase()).toSet();
      final nilaiAsli = await db.rawQuery('''
        SELECT DISTINCT TRIM($kolomTransaksi) as v FROM transaksi
        WHERE $kolomTransaksi IS NOT NULL AND TRIM($kolomTransaksi) != ''
      ''');
      for (final row in nilaiAsli) {
        final v = row['v'] as String;
        if (!sudahAda.contains(v.toLowerCase())) {
          await db.insert(table, {'nama': v});
          sudahAda.add(v.toLowerCase());
        }
      }
    }

    await gabungkanKeMaster('master_motor', 'motor');
    await gabungkanKeMaster('master_warna_cat', 'warna_cat');
    await gabungkanKeMaster('master_warna_lis', 'warna_lis');

    // Index untuk mempercepat query yang sebelumnya melakukan full table scan
    // (dashboard, daftar transaksi, autocomplete barang).
    await db.execute('CREATE INDEX IF NOT EXISTS idx_order_items_transaksi_id ON order_items(transaksi_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transaksi_tanggal ON transaksi(tanggal)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_harga_bahan_nama ON harga_bahan(nama_barang)');

    // v6: Status Pembayaran (Belum Bayar/DP/Lunas/Piutang) + Status Pengambilan
    // (Belum/Sudah Diambil) sebagai kolom TERPISAH dari status pengerjaan lama
    // ('status': pending/antre/proses/selesai) — tidak menimpa kolom itu sama
    // sekali. Juga tabel BARU: `pembayaran` (histori tiap pembayaran masuk,
    // tidak pernah dihapus) dan `harga_kombinasi` + `harga_kombinasi_histori`
    // (harga otomatis berdasarkan Type Motor + Barang + Proses, sesuai
    // permintaan — terpisah dari `katalog_barang` yang tetap dipakai untuk
    // autocomplete nama barang seperti sebelumnya, TIDAK diubah/dihapus).
    await tambahKolom("status_pembayaran", "TEXT DEFAULT 'belum_bayar'");
    await tambahKolom('total_dibayar', 'REAL DEFAULT 0');
    await tambahKolom("status_pengambilan", "TEXT DEFAULT 'belum_diambil'");
    await tambahKolom('waktu_pengambilan', 'TEXT');

    // Tambah kolom "pemasukan" pada tabel kas_keluar yang sudah ada, supaya
    // pembayaran aktual dari pelanggan bisa dicatat sebagai penambah saldo
    // kas TANPA mengubah struktur/perhitungan pengeluaran yang sudah berjalan
    // (kolom pengeluaran_* & saldo_* lama tidak disentuh).
    final kolomKas = await db.rawQuery("PRAGMA table_info(kas_keluar)");
    final namaKolomKas = kolomKas.map((k) => k['name']).toSet();
    Future<void> tambahKolomKas(String nm, String tipe) async {
      if (!namaKolomKas.contains(nm)) {
        await db.execute("ALTER TABLE kas_keluar ADD COLUMN $nm $tipe");
      }
    }
    await tambahKolomKas('pemasukan_kas', 'REAL');
    await tambahKolomKas('pemasukan_vapor', 'REAL');
    await tambahKolomKas('pemasukan_alat', 'REAL');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pembayaran (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaksi_id INTEGER NOT NULL,
        nominal REAL NOT NULL,
        tanggal TEXT NOT NULL,
        catatan TEXT,
        kas_jenis TEXT NOT NULL DEFAULT 'kas'
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pembayaran_transaksi_id ON pembayaran(transaksi_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS harga_kombinasi (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        motor TEXT NOT NULL DEFAULT '',
        barang TEXT NOT NULL,
        proses TEXT NOT NULL DEFAULT '',
        harga REAL,
        updated_at TEXT
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_harga_kombinasi_unique ON harga_kombinasi(motor, barang, proses)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS harga_kombinasi_histori (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        motor TEXT, barang TEXT, proses TEXT,
        harga_lama REAL, harga_baru REAL,
        tanggal TEXT
      )
    ''');

    // Backfill sekali jalan dari order_items + transaksi lama, supaya harga
    // otomatis kombinasi langsung "belajar" dari histori transaksi yang
    // sudah ada (bukan mulai dari kosong). Data transaksi lama SENDIRI
    // sama sekali tidak diubah — ini cuma membaca lalu mengisi tabel baru.
    final adaHargaKombinasi = await db.rawQuery("SELECT COUNT(*) as c FROM harga_kombinasi");
    if ((adaHargaKombinasi.first['c'] as int) == 0) {
      final rowsLamaHarga = await db.rawQuery('''
        SELECT t.motor as motor, oi.barang as barang, t.proses as proses,
               oi.harga_satuan as harga_satuan, t.tanggal as tanggal
        FROM order_items oi
        JOIN transaksi t ON t.id = oi.transaksi_id
        WHERE oi.barang IS NOT NULL AND oi.barang != ''
        ORDER BY t.tanggal ASC, t.id ASC, oi.id ASC
      ''');
      for (final r in rowsLamaHarga) {
        final motorV = (r['motor'] as String? ?? '').trim();
        final barangV = (r['barang'] as String? ?? '').trim();
        final prosesV = (r['proses'] as String? ?? '').trim();
        final hargaV = (r['harga_satuan'] as num?)?.toDouble();
        if (barangV.isEmpty || hargaV == null) continue;
        // conflictAlgorithm.replace: karena data diurutkan tanggal ASC, nilai
        // yang tersimpan akhir adalah harga PALING BARU untuk kombinasi itu.
        await db.insert(
          'harga_kombinasi',
          {'motor': motorV, 'barang': barangV, 'proses': prosesV, 'harga': hargaV, 'updated_at': r['tanggal']},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    // v7: soft-delete (Aktif/Nonaktif) untuk 4 master data lama + tabel BARU
    // untuk Audit Log, Kelola Pelanggan, Kelola User, Riwayat Reset
    // Periode, dan Riwayat Backup. Tidak ada data lama yang dihapus/diubah
    // nilainya — hanya menambah kolom & tabel baru.
    for (final t in ['master_motor', 'master_warna_cat', 'master_warna_lis', 'master_proses']) {
      final kolomT = await db.rawQuery("PRAGMA table_info($t)");
      final namaKolomT = kolomT.map((k) => k['name']).toSet();
      if (!namaKolomT.contains('aktif')) {
        await db.execute("ALTER TABLE $t ADD COLUMN aktif INTEGER DEFAULT 1");
      }
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        waktu TEXT NOT NULL,
        aktor TEXT NOT NULL DEFAULT 'Admin',
        aksi TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_log_waktu ON audit_log(waktu)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS master_pelanggan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL,
        kontak TEXT,
        aktif INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS master_user (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'Admin',
        aktif INTEGER DEFAULT 1
      )
    ''');
    final adaUser = await db.rawQuery("SELECT COUNT(*) as c FROM master_user");
    if ((adaUser.first['c'] as int) == 0) {
      await db.insert('master_user', {'nama': 'Admin', 'role': 'Admin'});
    }

    // Kelola Pelanggan: isi otomatis dari nama-nama pelanggan (kolom `asal`)
    // yang sudah pernah dipakai di transaksi lama, supaya tidak mulai kosong.
    final sudahAdaPelanggan = (await db.query('master_pelanggan')).map((r) => (r['nama'] as String).trim().toLowerCase()).toSet();
    final pelangganAsli = await db.rawQuery('''
      SELECT DISTINCT TRIM(asal) as v FROM transaksi WHERE asal IS NOT NULL AND TRIM(asal) != ''
    ''');
    for (final row in pelangganAsli) {
      final v = row['v'] as String;
      if (!sudahAdaPelanggan.contains(v.toLowerCase())) {
        await db.insert('master_pelanggan', {'nama': v});
        sudahAdaPelanggan.add(v.toLowerCase());
      }
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS riwayat_periode (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        saldo_akhir_kas REAL NOT NULL,
        saldo_akhir_vapor REAL NOT NULL,
        saldo_akhir_alat REAL NOT NULL,
        keterangan TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS riwayat_backup (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        waktu TEXT NOT NULL,
        tipe TEXT NOT NULL,
        status TEXT NOT NULL,
        keterangan TEXT
      )
    ''');

    await db.insert('pengaturan', {'key': 'db_version', 'value': _dbVersion.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _seedMasterData(Database db, String table, List<String> defaults) async {
    final count = await db.rawQuery("SELECT COUNT(*) as c FROM $table");
    if ((count.first['c'] as int) == 0) {
      for (final d in defaults) {
        await db.insert(table, {'nama': d});
      }
    }
  }

  // ---------- PENGATURAN (key-value settings) ----------

  Future<String> getPengaturan(String key, {String defaultValue = ''}) async {
    final db = await database;
    final r = await db.query('pengaturan', where: 'key = ?', whereArgs: [key]);
    if (r.isEmpty || r.first['value'] == null) return defaultValue;
    return r.first['value'] as String;
  }

  Future<void> setPengaturan(String key, String value) async {
    final db = await database;
    await db.insert('pengaturan', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- AUDIT LOG ----------
  // Dicatat untuk setiap aksi penting (buat/ubah transaksi, ubah harga, ubah
  // status, tambah pembayaran, pengeluaran, penyesuaian saldo, ubah master
  // data). Tidak pernah dihapus lewat aplikasi.

  Future<void> catatAudit(String aksi, {String aktor = 'Admin'}) async {
    final db = await database;
    await db.insert('audit_log', {
      'waktu': DateTime.now().toIso8601String(),
      'aktor': aktor,
      'aksi': aksi,
    });
  }

  Future<List<Map<String, dynamic>>> getAuditLog({int limit = 200}) async {
    final db = await database;
    return await db.query('audit_log', orderBy: 'id DESC', limit: limit);
  }

  // ---------- MASTER DATA (CRUD generik) ----------

  Future<List<Map<String, dynamic>>> getMaster(String table, {bool termasukNonaktif = false}) async {
    final db = await database;
    if (termasukNonaktif) return await db.query(table, orderBy: 'aktif DESC, nama ASC');
    return await db.query(table, where: 'aktif = 1 OR aktif IS NULL', orderBy: 'nama ASC');
  }

  Future<int> insertMaster(String table, String nama) async {
    final db = await database;
    final id = await db.insert(table, {'nama': nama, 'aktif': 1});
    await catatAudit('Menambah data master "$nama" ke $table');
    return id;
  }

  Future<int> updateMaster(String table, int id, String nama) async {
    final db = await database;
    final hasil = await db.update(table, {'nama': nama}, where: 'id = ?', whereArgs: [id]);
    await catatAudit('Mengubah data master di $table menjadi "$nama"');
    return hasil;
  }

  // Kolom di tabel transaksi/order_items yang menyimpan nilai dari masing-
  // masing tabel master, dipakai untuk mengecek apakah suatu nilai master
  // sudah pernah dipakai di transaksi sebelum boleh dihapus permanen.
  static const Map<String, String> _kolomPemakaianMaster = {
    'master_motor': 'transaksi.motor',
    'master_warna_cat': 'order_items.warna_cat',
    'master_warna_lis': 'order_items.warna_lis',
    'master_proses': 'transaksi.proses',
  };

  Future<bool> masterSudahDipakai(String table, String nama) async {
    final kolom = _kolomPemakaianMaster[table];
    if (kolom == null) return false;
    final db = await database;
    final parts = kolom.split('.');
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM ${parts[0]} WHERE ${parts[1]} = ?', [nama]);
    return ((r.first['c'] as int?) ?? 0) > 0;
  }

  // Menghapus/menonaktifkan data master dengan aman:
  // - Kalau BELUM PERNAH dipakai di transaksi manapun -> hapus permanen.
  // - Kalau SUDAH PERNAH dipakai -> jangan hard delete, cukup nonaktifkan
  //   (aktif = 0) supaya transaksi lama tetap bisa menampilkan namanya,
  //   tapi tidak muncul lagi sebagai pilihan baru.
  // Return true kalau dihapus permanen, false kalau hanya dinonaktifkan.
  Future<bool> deleteMaster(String table, int id) async {
    final db = await database;
    final rowList = await db.query(table, where: 'id = ?', whereArgs: [id]);
    final nama = rowList.isNotEmpty ? (rowList.first['nama'] as String? ?? '') : '';
    final dipakai = await masterSudahDipakai(table, nama);
    if (dipakai) {
      await db.update(table, {'aktif': 0}, where: 'id = ?', whereArgs: [id]);
      await catatAudit('Menonaktifkan data master "$nama" di $table (sudah dipakai transaksi)');
      return false;
    } else {
      await db.delete(table, where: 'id = ?', whereArgs: [id]);
      await catatAudit('Menghapus data master "$nama" di $table (belum pernah dipakai)');
      return true;
    }
  }

  Future<void> toggleAktifMaster(String table, int id, bool aktif) async {
    final db = await database;
    await db.update(table, {'aktif': aktif ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    await catatAudit('Mengubah status ${aktif ? "Aktif" : "Nonaktif"} data master di $table');
  }

  // ---------- KELOLA PELANGGAN ----------

  Future<List<Map<String, dynamic>>> getPelanggan({bool termasukNonaktif = false}) async {
    final db = await database;
    if (termasukNonaktif) return await db.query('master_pelanggan', orderBy: 'aktif DESC, nama ASC');
    return await db.query('master_pelanggan', where: 'aktif = 1 OR aktif IS NULL', orderBy: 'nama ASC');
  }

  Future<int> insertPelanggan(String nama, {String? kontak}) async {
    final db = await database;
    final id = await db.insert('master_pelanggan', {'nama': nama, 'kontak': kontak, 'aktif': 1});
    await catatAudit('Menambah pelanggan baru "$nama"');
    return id;
  }

  Future<void> updatePelanggan(int id, String nama, {String? kontak}) async {
    final db = await database;
    await db.update('master_pelanggan', {'nama': nama, 'kontak': kontak}, where: 'id = ?', whereArgs: [id]);
    await catatAudit('Mengubah data pelanggan "$nama"');
  }

  Future<bool> deletePelanggan(int id) async {
    final db = await database;
    final rowList = await db.query('master_pelanggan', where: 'id = ?', whereArgs: [id]);
    final nama = rowList.isNotEmpty ? (rowList.first['nama'] as String? ?? '') : '';
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM transaksi WHERE asal = ?', [nama]);
    final dipakai = ((r.first['c'] as int?) ?? 0) > 0;
    if (dipakai) {
      await db.update('master_pelanggan', {'aktif': 0}, where: 'id = ?', whereArgs: [id]);
      await catatAudit('Menonaktifkan pelanggan "$nama" (sudah punya transaksi)');
      return false;
    } else {
      await db.delete('master_pelanggan', where: 'id = ?', whereArgs: [id]);
      await catatAudit('Menghapus pelanggan "$nama"');
      return true;
    }
  }

  // ---------- KELOLA KAS (label kustom, jenis kas tetap 3: kas/vapor/alat) ----------

  Future<Map<String, String>> getLabelKas() async {
    return {
      'kas': await getPengaturan('label_kas', defaultValue: 'KAS Umum'),
      'vapor': await getPengaturan('label_kas_vapor', defaultValue: 'KAS Vapor'),
      'alat': await getPengaturan('label_kas_alat', defaultValue: 'KAS Maintenance'),
    };
  }

  Future<void> setLabelKas(String jenis, String label) async {
    await setPengaturan('label_kas${jenis == 'kas' ? '' : '_$jenis'}', label);
    await catatAudit('Mengubah label kas "$jenis" menjadi "$label"');
  }

  Future<List<Map<String, dynamic>>> getUser({bool termasukNonaktif = false}) async {
    final db = await database;
    if (termasukNonaktif) return await db.query('master_user', orderBy: 'aktif DESC, nama ASC');
    return await db.query('master_user', where: 'aktif = 1 OR aktif IS NULL', orderBy: 'nama ASC');
  }

  Future<int> insertUser(String nama, String role) async {
    final db = await database;
    final id = await db.insert('master_user', {'nama': nama, 'role': role, 'aktif': 1});
    await catatAudit('Menambah user baru "$nama" ($role)');
    return id;
  }

  Future<void> updateUser(int id, String nama, String role) async {
    final db = await database;
    await db.update('master_user', {'nama': nama, 'role': role}, where: 'id = ?', whereArgs: [id]);
    await catatAudit('Mengubah data user "$nama"');
  }

  Future<void> toggleAktifUser(int id, bool aktif) async {
    final db = await database;
    await db.update('master_user', {'aktif': aktif ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    await catatAudit('Mengubah status ${aktif ? "Aktif" : "Nonaktif"} user');
  }

  // ---------- SALDO AWAL / RESET PERIODE ----------
  // TIDAK menghapus histori kas_keluar/pembayaran/pengeluaran lama. Hanya
  // mencatat saldo akhir periode berjalan ke riwayat_periode, lalu menambah
  // baris baru di kas_keluar yang mereset saldo_* ke 0 sebagai titik awal
  // periode berikutnya.

  Future<void> resetPeriode({String? keterangan}) async {
    final db = await database;
    final saldoSekarang = await getSaldoTerakhir();
    final tanggal = DateTime.now().toIso8601String().substring(0, 10);

    await db.insert('riwayat_periode', {
      'tanggal': tanggal,
      'saldo_akhir_kas': saldoSekarang['kas'] ?? 0,
      'saldo_akhir_vapor': saldoSekarang['vapor'] ?? 0,
      'saldo_akhir_alat': saldoSekarang['alat'] ?? 0,
      'keterangan': keterangan ?? '',
    });

    await db.insert('kas_keluar', {
      'tanggal': tanggal,
      'catatan': 'Saldo Awal Periode Baru (reset)',
      'saldo_kas': 0,
      'saldo_kas_vapor': 0,
      'saldo_kas_alat': 0,
    });

    await catatAudit('Reset periode pembukuan baru (saldo awal Rp0)');
  }

  Future<List<Map<String, dynamic>>> getRiwayatPeriode() async {
    final db = await database;
    return await db.query('riwayat_periode', orderBy: 'id DESC');
  }

  // ---------- RIWAYAT BACKUP ----------

  Future<void> catatRiwayatBackup({required String tipe, required String status, String? keterangan}) async {
    final db = await database;
    await db.insert('riwayat_backup', {
      'waktu': DateTime.now().toIso8601String(),
      'tipe': tipe, // 'manual' | 'otomatis' | 'restore'
      'status': status, // 'berhasil' | 'gagal'
      'keterangan': keterangan ?? '',
    });
  }

  Future<List<Map<String, dynamic>>> getRiwayatBackup({int limit = 100}) async {
    final db = await database;
    return await db.query('riwayat_backup', orderBy: 'id DESC', limit: limit);
  }

  // ---------- ORDER (HEADER + ITEMS) ----------

  Future<String> generateNoTransaksi() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM transaksi');
    final n = (r.first['c'] as int) + 1;
    return 'TRX-${n.toString().padLeft(5, '0')}';
  }

  Future<int> insertOrder({
    required Map<String, dynamic> header,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await database;
    final id = await db.insert('transaksi', header);
    for (final item in items) {
      item['transaksi_id'] = id;
      await db.insert('order_items', item);
    }
    await catatAudit('Membuat transaksi baru ${header['no_transaksi'] ?? '#$id'} (${header['asal'] ?? '-'})');
    return id;
  }

  Future<void> updateOrder({
    required int id,
    required Map<String, dynamic> header,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await database;
    await db.update('transaksi', header, where: 'id = ?', whereArgs: [id]);
    await db.delete('order_items', where: 'transaksi_id = ?', whereArgs: [id]);
    for (final item in items) {
      item['transaksi_id'] = id;
      await db.insert('order_items', item);
    }
    await catatAudit('Mengubah transaksi ${header['no_transaksi'] ?? '#$id'}');
  }

  Future<Map<String, dynamic>?> getOrderHeader(int id) async {
    final db = await database;
    final r = await db.query('transaksi', where: 'id = ?', whereArgs: [id]);
    return r.isNotEmpty ? r.first : null;
  }

  Future<List<Map<String, dynamic>>> getOrderItems(int transaksiId) async {
    final db = await database;
    return await db.query('order_items', where: 'transaksi_id = ?', whereArgs: [transaksiId]);
  }

  // Rentang [awal, akhir) satu bulan dalam format 'YYYY-MM-DD', dipakai untuk
  // perbandingan langsung pada kolom tanggal (bukan strftime(...) = ?),
  // supaya index idx_transaksi_tanggal bisa dipakai SQLite alih-alih full
  // table scan setiap kali.
  (String, String) _rentangBulan(int bulan, int tahun) {
    final awal = '$tahun-${bulan.toString().padLeft(2, '0')}-01';
    final bulanBerikut = bulan == 12 ? 1 : bulan + 1;
    final tahunBerikut = bulan == 12 ? tahun + 1 : tahun;
    final akhir = '$tahunBerikut-${bulanBerikut.toString().padLeft(2, '0')}-01';
    return (awal, akhir);
  }

  // Dipakai halaman Transaksi supaya dropdown filter Bulan/Tahun HANYA
  // menampilkan periode yang benar-benar ada transaksinya di database
  // (bukan daftar 12 bulan/rentang tahun tetap seperti sebelumnya).
  Future<List<int>> getTahunTransaksiTersedia() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT substr(tanggal, 1, 4) as th FROM transaksi
      WHERE tanggal IS NOT NULL AND tanggal != ''
      ORDER BY th DESC
    ''');
    return rows.map((r) => int.parse(r['th'] as String)).toList();
  }

  Future<List<int>> getBulanTransaksiTersedia(int tahun) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT substr(tanggal, 6, 2) as bl FROM transaksi
      WHERE substr(tanggal, 1, 4) = ?
      ORDER BY bl DESC
    ''', ['$tahun']);
    return rows.map((r) => int.parse(r['bl'] as String)).toList();
  }

  Future<List<Map<String, dynamic>>> getTransaksiByBulan(int bulan, int tahun, {String search = ''}) async {
    final db = await database;
    final (awal, akhir) = _rentangBulan(bulan, tahun);
    final likeSearch = '%$search%';
    return await db.rawQuery('''
      SELECT t.*,
        (SELECT GROUP_CONCAT(barang, ', ') FROM order_items WHERE transaksi_id = t.id) as daftar_barang,
        (SELECT COUNT(*) FROM order_items WHERE transaksi_id = t.id) as jumlah_item,
        (SELECT SUM(harga) FROM order_items WHERE transaksi_id = t.id) as total_harga
      FROM transaksi t
      WHERE t.tanggal >= ? AND t.tanggal < ?
        AND (t.asal LIKE ? OR t.motor LIKE ? OR EXISTS (
          SELECT 1 FROM order_items oi WHERE oi.transaksi_id = t.id AND oi.barang LIKE ?
        ))
      ORDER BY t.tanggal DESC, t.id DESC
    ''', [awal, akhir, likeSearch, likeSearch, likeSearch]);
  }

  // Pencarian + filter transaksi yang lebih lengkap: dipakai halaman Transaksi
  // saat salah satu filter tambahan (status/motor/proses/rentang tanggal)
  // aktif. Kalau filter tanggal custom diisi, itu MENGGANTIKAN filter
  // bulan/tahun biasa; kalau tidak, tetap pakai bulan/tahun seperti biasa.
  Future<List<Map<String, dynamic>>> cariTransaksi({
    int? bulan,
    int? tahun,
    String search = '',
    String? statusPengerjaan, // null/'' = semua
    String? statusPengambilan,
    String? statusPembayaran,
    String? motor,
    String? proses,
    DateTime? tanggalMulai,
    DateTime? tanggalSelesai,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];

    if (tanggalMulai != null && tanggalSelesai != null) {
      where.add('t.tanggal >= ? AND t.tanggal <= ?');
      args.add(tanggalMulai.toIso8601String().substring(0, 10));
      args.add(tanggalSelesai.toIso8601String().substring(0, 10));
    } else if (bulan != null && tahun != null) {
      final (awal, akhir) = _rentangBulan(bulan, tahun);
      where.add('t.tanggal >= ? AND t.tanggal < ?');
      args.add(awal);
      args.add(akhir);
    }

    if (search.isNotEmpty) {
      where.add('''(t.asal LIKE ? OR t.motor LIKE ? OR t.proses LIKE ? OR t.no_transaksi LIKE ? OR EXISTS (
        SELECT 1 FROM order_items oi WHERE oi.transaksi_id = t.id AND oi.barang LIKE ?
      ))''');
      final like = '%$search%';
      args.addAll([like, like, like, like, like]);
    }
    if (statusPengerjaan != null && statusPengerjaan.isNotEmpty) {
      where.add('t.status = ?');
      args.add(statusPengerjaan);
    }
    if (statusPengambilan != null && statusPengambilan.isNotEmpty) {
      where.add('COALESCE(t.status_pengambilan, "belum_diambil") = ?');
      args.add(statusPengambilan);
    }
    if (statusPembayaran != null && statusPembayaran.isNotEmpty) {
      where.add('COALESCE(t.status_pembayaran, "belum_bayar") = ?');
      args.add(statusPembayaran);
    }
    if (motor != null && motor.isNotEmpty) {
      where.add('t.motor = ?');
      args.add(motor);
    }
    if (proses != null && proses.isNotEmpty) {
      where.add('t.proses = ?');
      args.add(proses);
    }

    final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return await db.rawQuery('''
      SELECT t.*,
        (SELECT GROUP_CONCAT(barang, ', ') FROM order_items WHERE transaksi_id = t.id) as daftar_barang,
        (SELECT COUNT(*) FROM order_items WHERE transaksi_id = t.id) as jumlah_item,
        (SELECT SUM(harga) FROM order_items WHERE transaksi_id = t.id) as total_harga
      FROM transaksi t
      $whereClause
      ORDER BY t.tanggal DESC, t.id DESC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getOrderTerbaru({int limit = 15}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT t.*,
        (SELECT GROUP_CONCAT(barang, ', ') FROM order_items WHERE transaksi_id = t.id) as daftar_barang,
        (SELECT GROUP_CONCAT(warna_cat, ', ') FROM order_items WHERE transaksi_id = t.id) as daftar_warna_cat,
        (SELECT GROUP_CONCAT(warna_lis, ', ') FROM order_items WHERE transaksi_id = t.id AND warna_lis IS NOT NULL AND warna_lis != '') as daftar_warna_lis,
        (SELECT SUM(harga) FROM order_items WHERE transaksi_id = t.id) as total_harga
      FROM transaksi t
      ORDER BY t.tanggal DESC, t.id DESC
      LIMIT ?
    ''', [limit]);
  }

  // ---------- DASHBOARD ----------

  Future<Map<String, dynamic>> getRingkasanBulanIni({int? bulan, int? tahun}) async {
    final db = await database;
    final now = DateTime.now();
    final (awal, akhir) = _rentangBulan(bulan ?? now.month, tahun ?? now.year);

    // Semua query ini independen satu sama lain, jadi dijalankan paralel
    // dengan Future.wait alih-alih menunggu satu-satu secara berurutan.
    final results = await Future.wait([
      db.rawQuery('''
        SELECT SUM(oi.harga) as total
        FROM order_items oi
        JOIN transaksi t ON t.id = oi.transaksi_id
        WHERE t.tanggal >= ? AND t.tanggal < ?
      ''', [awal, akhir]),
      db.rawQuery('''
        SELECT SUM(bagian_langgeng) as langgeng, SUM(bagian_juki) as juki, SUM(bagian_rio) as rio
        FROM transaksi
        WHERE tanggal >= ? AND tanggal < ?
      ''', [awal, akhir]),
      db.rawQuery('''
        SELECT status, COUNT(*) as c FROM transaksi
        WHERE tanggal >= ? AND tanggal < ?
        GROUP BY status
      ''', [awal, akhir]),
      // Belum Diambil: snapshot KESELURUHAN (bukan dibatasi bulan yang dipilih)
      // karena ini status operasional saat ini, bukan riwayat bulan tertentu.
      db.rawQuery('''
        SELECT COUNT(*) as c FROM transaksi
        WHERE status = 'selesai' AND (status_pengambilan IS NULL OR status_pengambilan = 'belum_diambil')
      '''),
      // Piutang: total sisa tagihan dari SEMUA transaksi berstatus piutang,
      // juga snapshot keseluruhan (bukan dibatasi bulan).
      db.rawQuery('''
        SELECT t.id as id, t.total_dibayar as total_dibayar,
          (SELECT SUM(harga) FROM order_items WHERE transaksi_id = t.id) as total_harga
        FROM transaksi t WHERE t.status_pembayaran = 'piutang'
      '''),
      // Pengeluaran bulan berjalan (sesuai periode yang dipilih), dari ketiga
      // jenis kas sekaligus.
      db.rawQuery('''
        SELECT SUM(COALESCE(pengeluaran_kas,0) + COALESCE(pengeluaran_vapor,0) + COALESCE(pengeluaran_alat,0)) as total
        FROM kas_keluar WHERE tanggal >= ? AND tanggal < ?
      ''', [awal, akhir]),
    ]);

    final omzetRow = results[0];
    final bagianRow = results[1];
    final statusCount = results[2];
    final belumDiambilRow = results[3];
    final piutangRows = results[4];
    final pengeluaranRow = results[5];

    final counts = {'pending': 0, 'antre': 0, 'proses': 0, 'selesai': 0};
    int total = 0;
    for (final s in statusCount) {
      final st = s['status'] as String? ?? 'pending';
      final c = s['c'] as int;
      if (counts.containsKey(st)) counts[st] = c;
      total += c;
    }

    double totalPiutang = 0;
    for (final r in piutangRows) {
      final th = (r['total_harga'] as num?)?.toDouble() ?? 0;
      final td = (r['total_dibayar'] as num?)?.toDouble() ?? 0;
      if (th > td) totalPiutang += (th - td);
    }

    final omzet = (omzetRow.first['total'] as num?)?.toDouble() ?? 0;
    final pengeluaran = (pengeluaranRow.first['total'] as num?)?.toDouble() ?? 0;

    return {
      'omzet': omzet,
      'langgeng': bagianRow.first['langgeng'] ?? 0,
      'juki': bagianRow.first['juki'] ?? 0,
      'rio': bagianRow.first['rio'] ?? 0,
      'total_transaksi': total,
      'selesai': counts['selesai'],
      'proses': counts['proses'],
      'antre': counts['antre'],
      'pending': counts['pending'],
      'belum_diambil': (belumDiambilRow.first['c'] as int?) ?? 0,
      'piutang': totalPiutang,
      'pengeluaran': pengeluaran,
      'laba_bersih': omzet - pengeluaran,
    };
  }

  Future<List<Map<String, dynamic>>> getGrafikOmzet(int jumlahBulan) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT strftime('%Y-%m', t.tanggal) as bulan, SUM(oi.harga) as omzet
      FROM transaksi t LEFT JOIN order_items oi ON oi.transaksi_id = t.id
      GROUP BY bulan
      ORDER BY bulan DESC
      LIMIT ?
    ''', [jumlahBulan]);
  }

  // Daftar bulan & tahun yang BENAR-BENAR ada datanya di tabel transaksi,
  // dipakai supaya dropdown "Pilih Bulan & Tahun" (dashboard) tidak
  // menampilkan bulan/tahun kosong yang tidak ada transaksinya sama sekali.
  // Dikembalikan urut terbaru dulu, format 'YYYY-MM'.
  Future<List<String>> getBulanTahunTersedia() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT strftime('%Y-%m', tanggal) as bulan
      FROM transaksi
      WHERE tanggal IS NOT NULL
      ORDER BY bulan DESC
    ''');
    return rows.map((r) => r['bulan'] as String).where((s) => s.isNotEmpty).toList();
  }

  // ---------- HARGA BAHAN (autocomplete barang/part) ----------

  // ---------- KATALOG BARANG (autocomplete barang/part yang dikerjakan) ----------
  // Terpisah dari harga_bahan (itu catatan pembelian material, bukan katalog part).

  Future<List<Map<String, dynamic>>> cariBarang(String q) async {
    final db = await database;
    if (q.isEmpty) return [];
    return await db.query(
      'katalog_barang',
      where: 'nama_barang LIKE ? AND aktif = 1',
      whereArgs: ['%$q%'],
      orderBy: 'nama_barang ASC',
      limit: 8,
    );
  }

  // Dipanggil setiap kali barang disimpan ke sebuah order: kalau nama belum
  // ada di katalog, ditambahkan; kalau sudah ada, harga_terakhir diperbarui
  // supaya saran harga di transaksi berikutnya selalu yang paling baru.
  Future<void> insertOrUpdateKatalogBarang(String nama, double harga) async {
    final db = await database;
    final existing = await db.query('katalog_barang', where: 'nama_barang = ? COLLATE NOCASE', whereArgs: [nama]);
    if (existing.isEmpty) {
      await db.insert('katalog_barang', {'nama_barang': nama, 'harga_terakhir': harga});
    } else {
      await db.update('katalog_barang', {'harga_terakhir': harga}, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  }

  // Dipakai halaman "Kelola Barang" (Prioritas 3, master data eksplisit).
  Future<List<Map<String, dynamic>>> getKatalogBarang({bool termasukNonaktif = false}) async {
    final db = await database;
    if (termasukNonaktif) return await db.query('katalog_barang', orderBy: 'aktif DESC, nama_barang ASC');
    return await db.query('katalog_barang', where: 'aktif = 1', orderBy: 'nama_barang ASC');
  }

  Future<int> insertKatalogBarangManual(String nama) async {
    final db = await database;
    final id = await db.insert('katalog_barang', {'nama_barang': nama, 'aktif': 1});
    await catatAudit('Menambah barang baru "$nama" ke katalog');
    return id;
  }

  Future<void> updateKatalogBarangNama(int id, String nama) async {
    final db = await database;
    await db.update('katalog_barang', {'nama_barang': nama}, where: 'id = ?', whereArgs: [id]);
    await catatAudit('Mengubah nama barang di katalog menjadi "$nama"');
  }

  Future<void> toggleAktifKatalogBarang(int id, bool aktif) async {
    final db = await database;
    await db.update('katalog_barang', {'aktif': aktif ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    await catatAudit('Mengubah status ${aktif ? "Aktif" : "Nonaktif"} barang di katalog');
  }

  Future<bool> deleteKatalogBarang(int id) async {
    final db = await database;
    final rowList = await db.query('katalog_barang', where: 'id = ?', whereArgs: [id]);
    final nama = rowList.isNotEmpty ? (rowList.first['nama_barang'] as String? ?? '') : '';
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM order_items WHERE barang = ?', [nama]);
    final dipakai = ((r.first['c'] as int?) ?? 0) > 0;
    if (dipakai) {
      await db.update('katalog_barang', {'aktif': 0}, where: 'id = ?', whereArgs: [id]);
      await catatAudit('Menonaktifkan barang "$nama" di katalog (sudah dipakai transaksi)');
      return false;
    } else {
      await db.delete('katalog_barang', where: 'id = ?', whereArgs: [id]);
      await catatAudit('Menghapus barang "$nama" dari katalog');
      return true;
    }
  }

  // ---------- HARGA BAHAN (catatan pembelian material/bahan habis pakai) ----------
  // CATATAN: tabel ini TIDAK dipakai untuk autocomplete barang/part order lagi
  // (lihat katalog_barang di atas). Dibiarkan apa adanya untuk kebutuhan lain.

  Future<int> insertHargaBahan(String nama, double harga) async {
    final db = await database;
    return await db.insert('harga_bahan', {'nama_barang': nama, 'harga': harga});
  }

  // ---------- HARGA KOMBINASI (Type Motor + Barang + Proses) ----------

  // Dasar "harga otomatis" utama: dicari berdasarkan kombinasi motor+barang+
  // proses. Kalau belum pernah ada kombinasi itu, caller (UI) akan fallback
  // ke harga_terakhir per-nama-barang saja (katalog_barang, seperti semula).
  Future<double?> cariHargaKombinasi(String motor, String barang, String proses) async {
    final db = await database;
    final r = await db.query(
      'harga_kombinasi',
      where: 'motor = ? COLLATE NOCASE AND barang = ? COLLATE NOCASE AND proses = ? COLLATE NOCASE',
      whereArgs: [motor.trim(), barang.trim(), proses.trim()],
    );
    if (r.isEmpty || r.first['harga'] == null) return null;
    return (r.first['harga'] as num).toDouble();
  }

  // Dipanggil setiap kali barang disimpan ke sebuah order (sama seperti
  // insertOrUpdateKatalogBarang, tapi per kombinasi). Histori harga LAMA
  // selalu disimpan ke harga_kombinasi_histori sebelum ditimpa — tidak pernah
  // dihapus.
  Future<void> insertOrUpdateHargaKombinasi(String motor, String barang, String proses, double harga) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final m = motor.trim();
    final b = barang.trim();
    final p = proses.trim();
    final existing = await db.query(
      'harga_kombinasi',
      where: 'motor = ? COLLATE NOCASE AND barang = ? COLLATE NOCASE AND proses = ? COLLATE NOCASE',
      whereArgs: [m, b, p],
    );
    if (existing.isEmpty) {
      await db.insert('harga_kombinasi', {'motor': m, 'barang': b, 'proses': p, 'harga': harga, 'updated_at': now});
    } else {
      final hargaLama = (existing.first['harga'] as num?)?.toDouble();
      if (hargaLama != null && hargaLama != harga) {
        await db.insert('harga_kombinasi_histori', {
          'motor': m, 'barang': b, 'proses': p,
          'harga_lama': hargaLama, 'harga_baru': harga, 'tanggal': now,
        });
      }
      await db.update('harga_kombinasi', {'harga': harga, 'updated_at': now}, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  }

  // ---------- STATUS PENGERJAAN / PENGAMBILAN / PEMBAYARAN ----------

  double _hitungTotalHarga(List<Map<String, dynamic>> items) =>
      items.fold(0.0, (sum, it) => sum + ((it['harga'] as num?)?.toDouble() ?? 0));

  // Aturan status pembayaran otomatis:
  //  - belum ada pembayaran sama sekali -> Belum Bayar
  //  - sudah bayar sebagian (< total)   -> DP, KECUALI barang sudah diambil
  //    tapi belum lunas -> Piutang
  //  - sudah bayar >= total             -> Lunas
  String hitungStatusPembayaran(double totalDibayar, double totalHarga, String statusPengambilan) {
    if (totalHarga <= 0 || totalDibayar <= 0) return 'belum_bayar';
    if (totalDibayar >= totalHarga) return 'lunas';
    return statusPengambilan == 'sudah_diambil' ? 'piutang' : 'dp';
  }

  Future<void> updateStatusPengerjaan(int id, String status) async {
    final db = await database;
    await db.update('transaksi', {'status': status}, where: 'id = ?', whereArgs: [id]);
    final header = await getOrderHeader(id);
    await catatAudit('Mengubah status pengerjaan ${header?['no_transaksi'] ?? '#$id'} menjadi "$status"');
  }

  // Status pengambilan HANYA boleh 'sudah_diambil' ketika pengerjaan sudah
  // 'selesai' — validasi juga dilakukan di UI, tapi dijaga lagi di sini.
  Future<void> updateStatusPengambilan(int id, String status) async {
    final db = await database;
    final header = await getOrderHeader(id);
    if (status == 'sudah_diambil' && (header?['status'] as String?) != 'selesai') {
      throw Exception('Barang belum bisa diambil sebelum status pengerjaan Selesai');
    }
    await db.update('transaksi', {
      'status_pengambilan': status,
      'waktu_pengambilan': status == 'sudah_diambil' ? DateTime.now().toIso8601String() : null,
    }, where: 'id = ?', whereArgs: [id]);

    // status pembayaran ikut disesuaikan (mis. DP yang barangnya sudah
    // diambil otomatis jadi Piutang)
    final items = await getOrderItems(id);
    final totalHarga = _hitungTotalHarga(items);
    final totalDibayar = (header?['total_dibayar'] as num?)?.toDouble() ?? 0;
    final statusBayarBaru = hitungStatusPembayaran(totalDibayar, totalHarga, status);
    await db.update('transaksi', {'status_pembayaran': statusBayarBaru}, where: 'id = ?', whereArgs: [id]);
    await catatAudit('Mengubah status pengambilan ${header?['no_transaksi'] ?? '#$id'} menjadi "$status"');
  }

  Future<List<Map<String, dynamic>>> getHistoriPembayaran(int transaksiId) async {
    final db = await database;
    return await db.query('pembayaran', where: 'transaksi_id = ?', whereArgs: [transaksiId], orderBy: 'tanggal DESC, id DESC');
  }

  // Mencatat pembayaran BARU dari pelanggan: masuk ke histori `pembayaran`
  // (tidak pernah dihapus), menambah saldo kas sesuai jenis kas yang dipilih
  // (HANYA nominal pembayaran aktual ini, bukan total transaksi), lalu
  // memperbarui total_dibayar & status_pembayaran transaksi tsb.
  Future<Map<String, dynamic>> tambahPembayaran({
    required int transaksiId,
    required double nominal,
    required String tanggal,
    String catatan = '',
    required String kasJenis, // 'kas' | 'vapor' | 'alat'
  }) async {
    final db = await database;
    final header = await getOrderHeader(transaksiId);
    if (header == null) throw Exception('Transaksi tidak ditemukan');

    await db.insert('pembayaran', {
      'transaksi_id': transaksiId,
      'nominal': nominal,
      'tanggal': tanggal,
      'catatan': catatan,
      'kas_jenis': kasJenis,
    });

    final saldoSekarang = await getSaldoTerakhir();
    final saldoBaru = (saldoSekarang[kasJenis] ?? 0) + nominal;
    final noTrx = header['no_transaksi'] ?? '-';
    final dataKas = <String, dynamic>{
      'tanggal': tanggal,
      'catatan': catatan.isNotEmpty ? catatan : 'Pembayaran $noTrx',
    };
    if (kasJenis == 'kas') { dataKas['pemasukan_kas'] = nominal; dataKas['saldo_kas'] = saldoBaru; }
    else if (kasJenis == 'vapor') { dataKas['pemasukan_vapor'] = nominal; dataKas['saldo_kas_vapor'] = saldoBaru; }
    else { dataKas['pemasukan_alat'] = nominal; dataKas['saldo_kas_alat'] = saldoBaru; }
    await db.insert('kas_keluar', dataKas);

    final items = await getOrderItems(transaksiId);
    final totalHarga = _hitungTotalHarga(items);
    final totalDibayarBaru = ((header['total_dibayar'] as num?)?.toDouble() ?? 0) + nominal;
    final statusPengambilan = (header['status_pengambilan'] as String?) ?? 'belum_diambil';
    final statusBaru = hitungStatusPembayaran(totalDibayarBaru, totalHarga, statusPengambilan);

    await db.update('transaksi', {
      'total_dibayar': totalDibayarBaru,
      'status_pembayaran': statusBaru,
    }, where: 'id = ?', whereArgs: [transaksiId]);

    await catatAudit('Menambah pembayaran $noTrx sebesar Rp${nominal.toStringAsFixed(0)}');

    return {'total_dibayar': totalDibayarBaru, 'status_pembayaran': statusBaru};
  }

  Future<Map<String, dynamic>?> getTransaksiDetail(int id) async {
    final header = await getOrderHeader(id);
    if (header == null) return null;
    final items = await getOrderItems(id);
    final pembayaranList = await getHistoriPembayaran(id);
    return {...header, 'items': items, 'pembayaran': pembayaranList, 'total_harga': _hitungTotalHarga(items)};
  }

  // ---------- KAS ----------

  Future<Map<String, double>> getSaldoTerakhir() async {
    final db = await database;
    Future<double> ambil(String kolom) async {
      final r = await db.rawQuery('SELECT $kolom AS v FROM kas_keluar WHERE $kolom IS NOT NULL ORDER BY id DESC LIMIT 1');
      if (r.isEmpty || r.first['v'] == null) return 0;
      return (r.first['v'] as num).toDouble();
    }
    return {
      'kas': await ambil('saldo_kas'),
      'vapor': await ambil('saldo_kas_vapor'),
      'alat': await ambil('saldo_kas_alat'),
    };
  }

  // Dipakai halaman Pengeluaran supaya dialog "Pilih Bulan & Tahun" HANYA
  // menampilkan periode yang benar-benar ada baris PENGELUARAN-nya (bukan
  // baris pemasukan/penyesuaian/reset saldo yang juga tersimpan di tabel
  // kas_keluar yang sama).
  Future<List<int>> getTahunPengeluaranTersedia() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT substr(tanggal, 1, 4) as th FROM kas_keluar
      WHERE tanggal IS NOT NULL AND tanggal != ''
        AND (pengeluaran_kas IS NOT NULL OR pengeluaran_vapor IS NOT NULL OR pengeluaran_alat IS NOT NULL)
      ORDER BY th DESC
    ''');
    return rows.map((r) => int.parse(r['th'] as String)).toList();
  }

  Future<List<int>> getBulanPengeluaranTersedia(int tahun) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT substr(tanggal, 6, 2) as bl FROM kas_keluar
      WHERE substr(tanggal, 1, 4) = ?
        AND (pengeluaran_kas IS NOT NULL OR pengeluaran_vapor IS NOT NULL OR pengeluaran_alat IS NOT NULL)
      ORDER BY bl DESC
    ''', ['$tahun']);
    return rows.map((r) => int.parse(r['bl'] as String)).toList();
  }

  Future<void> insertPengeluaran({required String jenis, required double nominal, required String catatan, required String tanggal}) async {
    final db = await database;
    final saldoSekarang = await getSaldoTerakhir();
    final saldoBaru = (saldoSekarang[jenis] ?? 0) - nominal;
    final data = <String, dynamic>{'tanggal': tanggal, 'catatan': catatan};
    if (jenis == 'kas') { data['pengeluaran_kas'] = nominal; data['saldo_kas'] = saldoBaru; }
    else if (jenis == 'vapor') { data['pengeluaran_vapor'] = nominal; data['saldo_kas_vapor'] = saldoBaru; }
    else { data['pengeluaran_alat'] = nominal; data['saldo_kas_alat'] = saldoBaru; }
    await db.insert('kas_keluar', data);
    await catatAudit('Menambahkan pengeluaran $jenis sebesar Rp${nominal.toStringAsFixed(0)} ($catatan)');
  }

  // Daftar pengeluaran (kas_keluar) untuk satu bulan tertentu, lengkap dengan
  // label sumber kas (Kas / Vapor / Maintenance) dan nominalnya masing-masing,
  // dipakai untuk menampilkan riwayat pengeluaran per bulan di halaman Pengeluaran.
  Future<List<Map<String, dynamic>>> getPengeluaranByBulan(int bulan, int tahun, {String? jenisKas, DateTime? tanggalMulai, DateTime? tanggalSelesai}) async {
    final db = await database;
    final where = <String>['(pengeluaran_kas IS NOT NULL OR pengeluaran_vapor IS NOT NULL OR pengeluaran_alat IS NOT NULL)'];
    final args = <dynamic>[];

    if (tanggalMulai != null && tanggalSelesai != null) {
      where.add('tanggal >= ? AND tanggal <= ?');
      args.add(tanggalMulai.toIso8601String().substring(0, 10));
      args.add(tanggalSelesai.toIso8601String().substring(0, 10));
    } else {
      final (awal, akhir) = _rentangBulan(bulan, tahun);
      where.add('tanggal >= ? AND tanggal < ?');
      args.add(awal);
      args.add(akhir);
    }

    if (jenisKas != null && jenisKas.isNotEmpty) {
      if (jenisKas == 'kas') where.add('pengeluaran_kas IS NOT NULL');
      if (jenisKas == 'vapor') where.add('pengeluaran_vapor IS NOT NULL');
      if (jenisKas == 'alat') where.add('pengeluaran_alat IS NOT NULL');
    }

    return await db.rawQuery('''
      SELECT id, tanggal, catatan,
        CASE
          WHEN pengeluaran_kas IS NOT NULL THEN 'Kas'
          WHEN pengeluaran_vapor IS NOT NULL THEN 'Vapor'
          WHEN pengeluaran_alat IS NOT NULL THEN 'Maintenance'
        END as sumber,
        COALESCE(pengeluaran_kas, pengeluaran_vapor, pengeluaran_alat) as nominal
      FROM kas_keluar
      WHERE ${where.join(' AND ')}
      ORDER BY tanggal DESC, id DESC
    ''', args);
  }

  // ---------- PENYESUAIAN SALDO ----------
  // Dipakai untuk mengoreksi selisih saldo sistem vs aktual (pengeluaran lama
  // yang tak tercatat, dsb) TANPA menghapus/mengubah histori transaksi lama.
  // Setiap penyesuaian tersimpan permanen di tabel penyesuaian_saldo.

  Future<void> _pastikanTabelPenyesuaian(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS penyesuaian_saldo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        jenis_kas TEXT NOT NULL,
        saldo_sebelum REAL NOT NULL,
        nominal_penyesuaian REAL NOT NULL,
        saldo_sesudah REAL NOT NULL,
        alasan TEXT NOT NULL,
        dibuat_oleh TEXT
      )
    ''');
  }

  Future<void> tambahPenyesuaianSaldo({
    required String jenisKas, // 'kas' | 'vapor' | 'alat'
    required double saldoAktual,
    required String alasan,
    String? user,
  }) async {
    final db = await database;
    await _pastikanTabelPenyesuaian(db);
    final saldoSekarang = await getSaldoTerakhir();
    final saldoSebelum = saldoSekarang[jenisKas] ?? 0;
    final selisih = saldoAktual - saldoSebelum;
    final now = DateTime.now().toIso8601String();
    final tanggal = now.substring(0, 10);

    await db.insert('penyesuaian_saldo', {
      'tanggal': tanggal,
      'jenis_kas': jenisKas,
      'saldo_sebelum': saldoSebelum,
      'nominal_penyesuaian': selisih,
      'saldo_sesudah': saldoAktual,
      'alasan': alasan,
      'dibuat_oleh': user ?? '-',
    });

    // Catat juga sebagai baris baru di kas_keluar supaya saldo terbaru
    // (getSaldoTerakhir) langsung ikut ter-update, konsisten dengan cara
    // pemasukan/pengeluaran lain dicatat. Baris ini ditandai lewat catatan.
    final data = <String, dynamic>{
      'tanggal': tanggal,
      'catatan': 'Penyesuaian saldo: $alasan',
    };
    if (jenisKas == 'kas') data['saldo_kas'] = saldoAktual;
    else if (jenisKas == 'vapor') data['saldo_kas_vapor'] = saldoAktual;
    else data['saldo_kas_alat'] = saldoAktual;
    await db.insert('kas_keluar', data);
    await catatAudit('Penyesuaian saldo $jenisKas: Rp${saldoSebelum.toStringAsFixed(0)} -> Rp${saldoAktual.toStringAsFixed(0)} ($alasan)');
  }

  Future<List<Map<String, dynamic>>> getHistoriPenyesuaianSaldo() async {
    final db = await database;
    await _pastikanTabelPenyesuaian(db);
    return await db.query('penyesuaian_saldo', orderBy: 'id DESC');
  }

  // ---------- LAPORAN KEUANGAN & TRANSAKSI ----------

  Future<Map<String, dynamic>> getLaporanKeuangan({required DateTime mulai, required DateTime selesai}) async {
    final db = await database;
    final awal = mulai.toIso8601String().substring(0, 10);
    // akhir bersifat inklusif -> dibandingkan '< akhir+1hari'
    final akhirEksklusif = selesai.add(const Duration(days: 1)).toIso8601String().substring(0, 10);

    final results = await Future.wait([
      db.rawQuery('''
        SELECT SUM(nominal) as total FROM pembayaran WHERE tanggal >= ? AND tanggal < ?
      ''', [awal, akhirEksklusif]),
      db.rawQuery('''
        SELECT SUM(COALESCE(pengeluaran_kas,0)+COALESCE(pengeluaran_vapor,0)+COALESCE(pengeluaran_alat,0)) as total
        FROM kas_keluar WHERE tanggal >= ? AND tanggal < ?
      ''', [awal, akhirEksklusif]),
      db.rawQuery('''
        SELECT t.id as id, t.total_dibayar as total_dibayar,
          (SELECT SUM(harga) FROM order_items WHERE transaksi_id = t.id) as total_harga
        FROM transaksi t WHERE t.status_pembayaran = 'piutang'
      '''),
      getSaldoTerakhir(),
    ]);

    final pemasukan = (results[0] as List).isNotEmpty ? ((results[0] as List).first['total'] as num?)?.toDouble() ?? 0 : 0.0;
    final pengeluaran = (results[1] as List).isNotEmpty ? ((results[1] as List).first['total'] as num?)?.toDouble() ?? 0 : 0.0;
    final piutangRows = results[2] as List<Map<String, dynamic>>;
    double totalPiutang = 0;
    for (final r in piutangRows) {
      final th = (r['total_harga'] as num?)?.toDouble() ?? 0;
      final td = (r['total_dibayar'] as num?)?.toDouble() ?? 0;
      if (th > td) totalPiutang += (th - td);
    }
    final saldo = results[3] as Map<String, double>;
    final totalSaldo = (saldo['kas'] ?? 0) + (saldo['vapor'] ?? 0) + (saldo['alat'] ?? 0);

    return {
      'pemasukan': pemasukan,
      'pengeluaran': pengeluaran,
      'saldo': totalSaldo,
      'piutang': totalPiutang,
      'laba_bersih': pemasukan - pengeluaran,
    };
  }

  Future<Map<String, dynamic>> getLaporanTransaksi({required DateTime mulai, required DateTime selesai}) async {
    final db = await database;
    final awal = mulai.toIso8601String().substring(0, 10);
    final akhirEksklusif = selesai.add(const Duration(days: 1)).toIso8601String().substring(0, 10);

    // Ditambahkan supaya Laporan Transaksi juga menampilkan: Total Omset,
    // pembagian Langgeng/Juki/Rio (sama seperti di Dashboard), serta uang
    // masuk kas/pengeluaran/laba bersih -- dihitung lewat getLaporanKeuangan()
    // yang sama persis dipakai Page Laporan Keuangan, supaya angkanya selalu
    // konsisten di semua halaman (dan di Export Laporan) untuk periode yang sama.
    final results = await Future.wait([
      db.rawQuery('''
        SELECT t.*, (SELECT SUM(harga) FROM order_items WHERE transaksi_id = t.id) as total_harga
        FROM transaksi t WHERE t.tanggal >= ? AND t.tanggal < ?
      ''', [awal, akhirEksklusif]),
      db.rawQuery('''
        SELECT SUM(bagian_langgeng) as langgeng, SUM(bagian_juki) as juki, SUM(bagian_rio) as rio
        FROM transaksi WHERE tanggal >= ? AND tanggal < ?
      '''  , [awal, akhirEksklusif]),
      // Total Omset: nilai seluruh barang/jasa pada transaksi periode ini
      // (bukan yang sudah dibayar saja) -- sama seperti kartu "Omset" di Dashboard.
      db.rawQuery('''
        SELECT SUM(oi.harga) as total
        FROM order_items oi
        JOIN transaksi t ON t.id = oi.transaksi_id
        WHERE t.tanggal >= ? AND t.tanggal < ?
      ''', [awal, akhirEksklusif]),
      getLaporanKeuangan(mulai: mulai, selesai: selesai),
    ]);

    final rows = results[0] as List<Map<String, dynamic>>;
    final bagianRow = results[1] as List<Map<String, dynamic>>;
    final omzetRow = results[2] as List<Map<String, dynamic>>;
    final keuangan = results[3] as Map<String, dynamic>;

    int total = rows.length, selesaiC = 0, prosesC = 0, antreC = 0, pendingC = 0;
    int belumDiambil = 0, lunasC = 0, dpC = 0, piutangC = 0;
    double totalPiutang = 0;

    for (final r in rows) {
      switch (r['status'] as String? ?? 'pending') {
        case 'selesai': selesaiC++; break;
        case 'proses': prosesC++; break;
        case 'antre': antreC++; break;
        default: pendingC++;
      }
      if ((r['status'] as String?) == 'selesai' && ((r['status_pengambilan'] as String?) ?? 'belum_diambil') == 'belum_diambil') {
        belumDiambil++;
      }
      final statusBayar = (r['status_pembayaran'] as String?) ?? 'belum_bayar';
      if (statusBayar == 'lunas') lunasC++;
      if (statusBayar == 'dp') dpC++;
      if (statusBayar == 'piutang') {
        piutangC++;
        final th = (r['total_harga'] as num?)?.toDouble() ?? 0;
        final td = (r['total_dibayar'] as num?)?.toDouble() ?? 0;
        if (th > td) totalPiutang += (th - td);
      }
    }

    return {
      'total_transaksi': total,
      'selesai': selesaiC,
      'proses': prosesC,
      'antre': antreC,
      'pending': pendingC,
      'belum_diambil': belumDiambil,
      'lunas': lunasC,
      'dp': dpC,
      'piutang_count': piutangC,
      'total_piutang': totalPiutang,
      'omzet': (omzetRow.first['total'] as num?) ?? 0,
      'uang_masuk_kas': keuangan['pemasukan'] ?? 0,
      'pengeluaran': keuangan['pengeluaran'] ?? 0,
      'laba_bersih': keuangan['laba_bersih'] ?? 0,
      'langgeng': bagianRow.first['langgeng'] ?? 0,
      'juki': bagianRow.first['juki'] ?? 0,
      'rio': bagianRow.first['rio'] ?? 0,
    };
  }
}