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
  static const int _dbVersion = 6;

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

  // ---------- MASTER DATA (CRUD generik) ----------

  Future<List<Map<String, dynamic>>> getMaster(String table) async {
    final db = await database;
    return await db.query(table, orderBy: 'nama ASC');
  }

  Future<int> insertMaster(String table, String nama) async {
    final db = await database;
    return await db.insert(table, {'nama': nama});
  }

  Future<int> updateMaster(String table, int id, String nama) async {
    final db = await database;
    return await db.update(table, {'nama': nama}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteMaster(String table, int id) async {
    final db = await database;
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
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

    // Ketiga query ini independen satu sama lain, jadi dijalankan paralel
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
    ]);

    final omzetRow = results[0];
    final bagianRow = results[1];
    final statusCount = results[2];

    final counts = {'pending': 0, 'antre': 0, 'proses': 0, 'selesai': 0};
    int total = 0;
    for (final s in statusCount) {
      final st = s['status'] as String? ?? 'pending';
      final c = s['c'] as int;
      if (counts.containsKey(st)) counts[st] = c;
      total += c;
    }

    return {
      'omzet': omzetRow.first['total'] ?? 0,
      'langgeng': bagianRow.first['langgeng'] ?? 0,
      'juki': bagianRow.first['juki'] ?? 0,
      'rio': bagianRow.first['rio'] ?? 0,
      'total_transaksi': total,
      'selesai': counts['selesai'],
      'proses': counts['proses'],
      'antre': counts['antre'],
      'pending': counts['pending'],
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

  Future<void> insertPengeluaran({required String jenis, required double nominal, required String catatan, required String tanggal}) async {
    final db = await database;
    final saldoSekarang = await getSaldoTerakhir();
    final saldoBaru = (saldoSekarang[jenis] ?? 0) - nominal;
    final data = <String, dynamic>{'tanggal': tanggal, 'catatan': catatan};
    if (jenis == 'kas') { data['pengeluaran_kas'] = nominal; data['saldo_kas'] = saldoBaru; }
    else if (jenis == 'vapor') { data['pengeluaran_vapor'] = nominal; data['saldo_kas_vapor'] = saldoBaru; }
    else { data['pengeluaran_alat'] = nominal; data['saldo_kas_alat'] = saldoBaru; }
    await db.insert('kas_keluar', data);
  }

  // Daftar pengeluaran (kas_keluar) untuk satu bulan tertentu, lengkap dengan
  // label sumber kas (Kas / Vapor / Maintenance) dan nominalnya masing-masing,
  // dipakai untuk menampilkan riwayat pengeluaran per bulan di halaman Pengeluaran.
  Future<List<Map<String, dynamic>>> getPengeluaranByBulan(int bulan, int tahun) async {
    final db = await database;
    final (awal, akhir) = _rentangBulan(bulan, tahun);
    return await db.rawQuery('''
      SELECT id, tanggal, catatan,
        CASE
          WHEN pengeluaran_kas IS NOT NULL THEN 'Kas'
          WHEN pengeluaran_vapor IS NOT NULL THEN 'Vapor'
          WHEN pengeluaran_alat IS NOT NULL THEN 'Maintenance'
        END as sumber,
        COALESCE(pengeluaran_kas, pengeluaran_vapor, pengeluaran_alat) as nominal
      FROM kas_keluar
      WHERE tanggal >= ? AND tanggal < ?
        AND (pengeluaran_kas IS NOT NULL OR pengeluaran_vapor IS NOT NULL OR pengeluaran_alat IS NOT NULL)
      ORDER BY tanggal DESC, id DESC
    ''', [awal, akhir]);
  }
}