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

  Future<void> _migrasi(Database db) async {
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

    for (final t in ['master_motor', 'master_warna_cat', 'master_warna_lis', 'master_proses']) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $t (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nama TEXT NOT NULL
        )
      ''');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pengaturan (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await _seedMasterData(db, 'master_motor', ['Tiger', 'MP', 'KPH', '5TP', 'KLX']);
    await _seedMasterData(db, 'master_warna_cat', ['Hitam Glossy', 'Gun Metal Glossy', 'Bronze Metalik Glossy', 'Hitam Textur']);
    await _seedMasterData(db, 'master_warna_lis', ['Merah', 'Biru', 'Kuning', 'Hijau', 'Putih', 'Pink', 'Ungu', 'Emas', 'Silver', 'Hitam']);
    await _seedMasterData(db, 'master_proses', ['PowderCoating & Vaporblasting', 'Powder Coating', 'Vaporblasting', 'Sandblasting', 'Remove Chrome, PowderCoating, Vaporblasting']);
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

  Future<List<Map<String, dynamic>>> getTransaksiByBulan(int bulan, int tahun, {String search = ''}) async {
    final db = await database;
    final bulanStr = bulan.toString().padLeft(2, '0');
    final likeSearch = '%$search%';
    return await db.rawQuery('''
      SELECT t.*,
        (SELECT GROUP_CONCAT(barang, ', ') FROM order_items WHERE transaksi_id = t.id) as daftar_barang,
        (SELECT COUNT(*) FROM order_items WHERE transaksi_id = t.id) as jumlah_item,
        (SELECT SUM(harga) FROM order_items WHERE transaksi_id = t.id) as total_harga
      FROM transaksi t
      WHERE strftime('%m', t.tanggal) = ? AND strftime('%Y', t.tanggal) = ?
        AND (t.asal LIKE ? OR t.motor LIKE ? OR EXISTS (
          SELECT 1 FROM order_items oi WHERE oi.transaksi_id = t.id AND oi.barang LIKE ?
        ))
      ORDER BY t.tanggal DESC, t.id DESC
    ''', [bulanStr, tahun.toString(), likeSearch, likeSearch, likeSearch]);
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

  Future<Map<String, dynamic>> getRingkasanBulanIni() async {
    final db = await database;
    final now = DateTime.now();
    final bulanStr = now.month.toString().padLeft(2, '0');
    final tahunStr = now.year.toString();

    final omzetRow = await db.rawQuery('''
      SELECT SUM(oi.harga) as total
      FROM order_items oi
      JOIN transaksi t ON t.id = oi.transaksi_id
      WHERE strftime('%m', t.tanggal) = ? AND strftime('%Y', t.tanggal) = ?
    ''', [bulanStr, tahunStr]);

    final bagianRow = await db.rawQuery('''
      SELECT SUM(bagian_langgeng) as langgeng, SUM(bagian_juki) as juki, SUM(bagian_rio) as rio
      FROM transaksi
      WHERE strftime('%m', tanggal) = ? AND strftime('%Y', tanggal) = ?
    ''', [bulanStr, tahunStr]);

    final statusCount = await db.rawQuery('''
      SELECT status, COUNT(*) as c FROM transaksi
      WHERE strftime('%m', tanggal) = ? AND strftime('%Y', tanggal) = ?
      GROUP BY status
    ''', [bulanStr, tahunStr]);

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

  Future<List<Map<String, dynamic>>> cariBarang(String q) async {
    final db = await database;
    if (q.isEmpty) return [];
    return await db.query('harga_bahan', where: 'nama_barang LIKE ?', whereArgs: ['%$q%'], limit: 8);
  }

  Future<int> insertHargaBahan(String nama, double harga) async {
    final db = await database;
    return await db.insert('harga_bahan', {'nama_barang': nama, 'harga': harga});
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
}