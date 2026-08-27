import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';

class KelolaBarangPage extends StatefulWidget {
  const KelolaBarangPage({super.key});
  @override
  State<KelolaBarangPage> createState() => _KelolaBarangPageState();
}

class _KelolaBarangPageState extends State<KelolaBarangPage> {
  List<Map<String, dynamic>> data = [];
  bool tampilkanNonaktif = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    data = await DatabaseHelper.instance.getKatalogBarang(termasukNonaktif: tampilkanNonaktif);
    setState(() {});
  }

  Future<void> _tambahEditDialog({Map<String, dynamic>? existing}) async {
    final c = TextEditingController(text: existing?['nama_barang'] ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Tambah Barang' : 'Edit Barang'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Nama Barang', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              if (c.text.trim().isEmpty) return;
              if (existing == null) {
                await DatabaseHelper.instance.insertKatalogBarangManual(c.text.trim());
              } else {
                await DatabaseHelper.instance.updateKatalogBarangNama(existing['id'], c.text.trim());
              }
              if (mounted) Navigator.pop(context);
              _load();
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
        content: Text('Kalau "${d['nama_barang']}" sudah pernah dipakai di transaksi, data tidak dihapus permanen — hanya dinonaktifkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lanjutkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final permanen = await DatabaseHelper.instance.deleteKatalogBarang(d['id']);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(permanen ? 'Barang dihapus' : 'Barang dinonaktifkan (sudah dipakai transaksi)')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Barang'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _tambahEditDialog())]),
      body: Column(children: [
        SwitchListTile(
          dense: true,
          title: const Text('Tampilkan yang Nonaktif', style: TextStyle(fontSize: 13)),
          value: tampilkanNonaktif,
          onChanged: (v) { setState(() => tampilkanNonaktif = v); _load(); },
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: data.length,
            itemBuilder: (_, i) {
              final d = data[i];
              final aktif = (d['aktif'] as int? ?? 1) == 1;
              return ListTile(
                title: Text(d['nama_barang'], style: TextStyle(color: aktif ? Colors.black : Colors.grey)),
                subtitle: Text(
                  '${d['harga_terakhir'] != null ? formatRupiah(d['harga_terakhir']) : 'Belum ada harga'}${aktif ? '' : ' • Nonaktif'}',
                  style: TextStyle(fontSize: 11, color: aktif ? Colors.grey : Colors.orange),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(value: aktif, onChanged: (v) async { await DatabaseHelper.instance.toggleAktifKatalogBarang(d['id'], v); _load(); }),
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

class KelolaPelangganPage extends StatefulWidget {
  const KelolaPelangganPage({super.key});
  @override
  State<KelolaPelangganPage> createState() => _KelolaPelangganPageState();
}

class _KelolaPelangganPageState extends State<KelolaPelangganPage> {
  List<Map<String, dynamic>> data = [];
  bool tampilkanNonaktif = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    data = await DatabaseHelper.instance.getPelanggan(termasukNonaktif: tampilkanNonaktif);
    setState(() {});
  }

  Future<void> _tambahEditDialog({Map<String, dynamic>? existing}) async {
    final nama = TextEditingController(text: existing?['nama'] ?? '');
    final kontak = TextEditingController(text: existing?['kontak'] ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Tambah Pelanggan' : 'Edit Pelanggan'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nama, decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: kontak, decoration: const InputDecoration(labelText: 'No. HP / Kontak (opsional)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              if (nama.text.trim().isEmpty) return;
              if (existing == null) {
                await DatabaseHelper.instance.insertPelanggan(nama.text.trim(), kontak: kontak.text.trim());
              } else {
                await DatabaseHelper.instance.updatePelanggan(existing['id'], nama.text.trim(), kontak: kontak.text.trim());
              }
              if (mounted) Navigator.pop(context);
              _load();
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
        title: const Text('Hapus pelanggan ini?'),
        content: Text('Kalau "${d['nama']}" sudah pernah bertransaksi, data tidak dihapus permanen — hanya dinonaktifkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lanjutkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final permanen = await DatabaseHelper.instance.deletePelanggan(d['id']);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(permanen ? 'Pelanggan dihapus' : 'Pelanggan dinonaktifkan (sudah punya transaksi)')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Pelanggan'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _tambahEditDialog())]),
      body: Column(children: [
        SwitchListTile(
          dense: true,
          title: const Text('Tampilkan yang Nonaktif', style: TextStyle(fontSize: 13)),
          value: tampilkanNonaktif,
          onChanged: (v) { setState(() => tampilkanNonaktif = v); _load(); },
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: data.length,
            itemBuilder: (_, i) {
              final d = data[i];
              final aktif = (d['aktif'] as int? ?? 1) == 1;
              final kontak = (d['kontak'] as String?)?.trim();
              return ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.hitamLogo, child: Icon(Icons.person, color: AppColors.biruTerang, size: 18)),
                title: Text(d['nama'], style: TextStyle(color: aktif ? Colors.black : Colors.grey)),
                subtitle: Text('${kontak != null && kontak.isNotEmpty ? kontak : 'Tanpa kontak'}${aktif ? '' : ' • Nonaktif'}', style: TextStyle(fontSize: 11, color: aktif ? Colors.grey : Colors.orange)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
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

class KelolaKasPage extends StatefulWidget {
  const KelolaKasPage({super.key});
  @override
  State<KelolaKasPage> createState() => _KelolaKasPageState();
}

class _KelolaKasPageState extends State<KelolaKasPage> {
  Map<String, String> label = {'kas': 'KAS Umum', 'vapor': 'KAS Vapor', 'alat': 'KAS Maintenance'};
  Map<String, double> saldo = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final l = await DatabaseHelper.instance.getLabelKas();
    final s = await DatabaseHelper.instance.getSaldoTerakhir();
    setState(() { label = l; saldo = s; loading = false; });
  }

  Future<void> _editLabel(String jenis) async {
    final c = TextEditingController(text: label[jenis]);
    final hasil = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ubah Nama Kas'),
        content: TextField(controller: c, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    if (hasil != null && hasil.isNotEmpty) {
      await DatabaseHelper.instance.setLabelKas(jenis, hasil);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Kas')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Aplikasi ini memakai 3 jenis kas tetap. Nama tampilannya bisa disesuaikan di sini.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                for (final jenis in ['kas', 'vapor', 'alat'])
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: AppColors.hitamLogo, child: Icon(Icons.account_balance_wallet, color: AppColors.biruTerang, size: 18)),
                      title: Text(label[jenis] ?? jenis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Saldo saat ini: ${formatRupiah(saldo[jenis] ?? 0)}', style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editLabel(jenis)),
                    ),
                  ),
              ],
            ),
    );
  }
}

class KelolaUserPage extends StatefulWidget {
  const KelolaUserPage({super.key});
  @override
  State<KelolaUserPage> createState() => _KelolaUserPageState();
}

class _KelolaUserPageState extends State<KelolaUserPage> {
  List<Map<String, dynamic>> data = [];
  bool tampilkanNonaktif = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    data = await DatabaseHelper.instance.getUser(termasukNonaktif: tampilkanNonaktif);
    setState(() {});
  }

  Future<void> _tambahEditDialog({Map<String, dynamic>? existing}) async {
    final nama = TextEditingController(text: existing?['nama'] ?? '');
    String role = existing?['role'] ?? 'Admin';
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Tambah User' : 'Edit User'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nama, decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                DropdownMenuItem(value: 'Kasir', child: Text('Kasir')),
                DropdownMenuItem(value: 'Teknisi', child: Text('Teknisi')),
              ],
              onChanged: (v) => setDialogState(() => role = v ?? 'Admin'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                if (nama.text.trim().isEmpty) return;
                if (existing == null) {
                  await DatabaseHelper.instance.insertUser(nama.text.trim(), role);
                } else {
                  await DatabaseHelper.instance.updateUser(existing['id'], nama.text.trim(), role);
                }
                if (mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola User'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _tambahEditDialog())]),
      body: Column(children: [
        SwitchListTile(
          dense: true,
          title: const Text('Tampilkan yang Nonaktif', style: TextStyle(fontSize: 13)),
          value: tampilkanNonaktif,
          onChanged: (v) { setState(() => tampilkanNonaktif = v); _load(); },
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: data.length,
            itemBuilder: (_, i) {
              final d = data[i];
              final aktif = (d['aktif'] as int? ?? 1) == 1;
              return ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.hitamLogo, child: Icon(Icons.badge, color: AppColors.biruTerang, size: 18)),
                title: Text(d['nama'], style: TextStyle(color: aktif ? Colors.black : Colors.grey)),
                subtitle: Text('${d['role']}${aktif ? '' : ' • Nonaktif'}', style: TextStyle(fontSize: 11, color: aktif ? Colors.grey : Colors.orange)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(value: aktif, onChanged: (v) async { await DatabaseHelper.instance.toggleAktifUser(d['id'], v); _load(); }),
                  IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _tambahEditDialog(existing: d)),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}
