import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';

class KasKeluarPage extends StatefulWidget {
  const KasKeluarPage({super.key});
  @override
  State<KasKeluarPage> createState() => _KasKeluarPageState();
}

class _KasKeluarPageState extends State<KasKeluarPage> {
  Map<String, double> saldo = {'kas': 0, 'vapor': 0, 'alat': 0};
  String jenis = 'kas';
  final _nominal = TextEditingController();
  final _catatan = TextEditingController();
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final s = await DatabaseHelper.instance.getSaldoTerakhir();
    setState(() {
      saldo = s;
      loading = false;
    });
  }

  Future<void> _simpan() async {
    final nominal = double.tryParse(_nominal.text.trim()) ?? 0;
    if (nominal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi nominal terlebih dahulu')));
      return;
    }
    setState(() => saving = true);
    await DatabaseHelper.instance.insertPengeluaran(
      jenis: jenis,
      nominal: nominal,
      catatan: _catatan.text.trim(),
      tanggal: DateTime.now().toIso8601String().substring(0, 10),
    );
    _nominal.clear();
    _catatan.clear();
    await _load();
    setState(() => saving = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengeluaran tersimpan')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kas Keluar')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  _saldoCard('Saldo KAS', saldo['kas']),
                  const SizedBox(width: 8),
                  _saldoCard('KAS Vapor', saldo['vapor']),
                  const SizedBox(width: 8),
                  _saldoCard('KAS Alat', saldo['alat']),
                ]),
                const SizedBox(height: 20),
                const Text('Jenis kas', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: jenis,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'kas', child: Text('KAS umum')),
                    DropdownMenuItem(value: 'vapor', child: Text('KAS Vapor')),
                    DropdownMenuItem(value: 'alat', child: Text('KAS Alat')),
                  ],
                  onChanged: (v) => setState(() => jenis = v ?? 'kas'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nominal,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal', hintText: 'Rp0', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _catatan,
                  decoration: const InputDecoration(labelText: 'Catatan', hintText: 'cth. Beli bubuk hitam', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: saving ? null : _simpan,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Simpan Pengeluaran'),
                ),
              ],
            ),
    );
  }

  Widget _saldoCard(String label, double? value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(formatRupiah(value ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}