import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';

// Halaman "Kelola Katalog Barang per Type Motor": CRUD daftar Barang/Part
// yang SENGAJA dikurasi manual untuk tiap Type Motor, lengkap dengan harga
// acuan (motor + barang, TANPA proses). Beda dengan saran otomatis di form
// order yang baru terbentuk setelah ada transaksi (harga_kombinasi) — di
// sini admin bisa mendaftarkan barang standar dari awal, sebelum motor itu
// pernah ditransaksikan sama sekali.
class KatalogBarangMotorPage extends StatefulWidget {
  const KatalogBarangMotorPage({super.key});
  @override
  State<KatalogBarangMotorPage> createState() => _KatalogBarangMotorPageState();
}

class _KatalogBarangMotorPageState extends State<KatalogBarangMotorPage> {
  List<Map<String, dynamic>> masterMotor = [];
  String? motorTerpilih;
  List<Map<String, dynamic>> data = [];
  bool tampilkanNonaktif = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadMotor();
  }

  Future<void> _loadMotor() async {
    masterMotor = await DatabaseHelper.instance.getMaster('master_motor');
    if (masterMotor.isNotEmpty) {
      motorTerpilih = masterMotor.first['nama'] as String;
    }
    await _loadBarang();
    setState(() => loading = false);
  }

  Future<void> _loadBarang() async {
    if (motorTerpilih == null) {
      data = [];
      setState(() {});
      return;
    }
    data = await DatabaseHelper.instance.getKatalogBarangMotor(motorTerpilih!, termasukNonaktif: tampilkanNonaktif);
    setState(() {});
  }

  Future<void> _tambahEditDialog({Map<String, dynamic>? existing}) async {
    if (motorTerpilih == null) return;
    final namaC = TextEditingController(text: existing?['nama_barang'] ?? '');
    final hargaC = TextEditingController(
      text: existing?['harga_acuan'] != null ? formatRupiah(existing!['harga_acuan'], withRp: false) : '',
    );
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Tambah Barang' : 'Edit Barang'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Type Motor: $motorTerpilih', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: namaC,
            decoration: const InputDecoration(labelText: 'Nama Barang / Part', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: hargaC,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Harga Acuan (opsional)',
              helperText: 'Patokan awal sebelum ada transaksi. Boleh dikosongkan.',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              if (namaC.text.trim().isEmpty) return;
              final harga = hargaC.text.trim().isEmpty ? null : parseRupiah(hargaC.text);
              if (existing == null) {
                await DatabaseHelper.instance.insertKatalogBarangMotor(motorTerpilih!, namaC.text.trim(), harga);
              } else {
                await DatabaseHelper.instance.updateKatalogBarangMotor(existing['id'], namaC.text.trim(), harga);
              }
              if (mounted) Navigator.pop(context);
              _loadBarang();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _hapus(Map<String, dynamic> d) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus barang ini?'),
        content: Text('Kalau "${d['nama_barang']}" sudah pernah dipakai di transaksi motor "$motorTerpilih", data tidak akan dihapus permanen — hanya dinonaktifkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lanjutkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final dihapusPermanen = await DatabaseHelper.instance.deleteKatalogBarangMotor(d['id']);
    await _loadBarang();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dihapusPermanen ? '"${d['nama_barang']}" dihapus' : '"${d['nama_barang']}" dinonaktifkan (sudah dipakai di transaksi)'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Katalog Barang'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: motorTerpilih == null ? null : () => _tambahEditDialog(),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : masterMotor.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Belum ada Type Motor. Tambahkan dulu lewat menu "Kelola Type Motor".', textAlign: TextAlign.center),
                  ),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: DropdownButtonFormField<String>(
                      initialValue: motorTerpilih,
                      decoration: const InputDecoration(labelText: 'Type Motor', border: OutlineInputBorder()),
                      items: masterMotor
                          .map((m) => DropdownMenuItem(value: m['nama'] as String, child: Text(m['nama'] as String)))
                          .toList(),
                      onChanged: (v) {
                        setState(() => motorTerpilih = v);
                        _loadBarang();
                      },
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Tampilkan yang Nonaktif', style: TextStyle(fontSize: 13)),
                    value: tampilkanNonaktif,
                    onChanged: (v) { setState(() => tampilkanNonaktif = v); _loadBarang(); },
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: data.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Belum ada barang di katalog untuk Type Motor "$motorTerpilih".\nTekan tombol + untuk menambahkan.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: data.length,
                            itemBuilder: (_, i) {
                              final d = data[i];
                              final aktif = (d['aktif'] as int? ?? 1) == 1;
                              final harga = d['harga_acuan'] as num?;
                              return ListTile(
                                title: Text(d['nama_barang'], style: TextStyle(color: aktif ? Colors.black : Colors.grey)),
                                subtitle: Text(
                                  '${harga != null ? formatRupiah(harga) : 'Belum ada harga acuan'}${aktif ? '' : ' • Nonaktif'}',
                                  style: TextStyle(fontSize: 12, color: aktif ? AppColors.biruTua : Colors.orange),
                                ),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Switch(
                                    value: aktif,
                                    onChanged: (v) async {
                                      await DatabaseHelper.instance.toggleAktifKatalogBarangMotor(d['id'], v);
                                      _loadBarang();
                                    },
                                  ),
                                  IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _tambahEditDialog(existing: d)),
                                  IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _hapus(d)),
                                ]),
                              );
                            },
                          ),
                  ),
                ]),
    );
  }
}
