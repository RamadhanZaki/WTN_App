import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';
import 'order_form_page.dart';

class TransaksiPage extends StatefulWidget {
  const TransaksiPage({super.key});
  @override
  State<TransaksiPage> createState() => _TransaksiPageState();
}

class _TransaksiPageState extends State<TransaksiPage> {
  int bulan = DateTime.now().month;
  int tahun = DateTime.now().year;
  String search = '';
  List<Map<String, dynamic>> data = [];
  bool loading = true;

  final bulanNama = const ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final d = await DatabaseHelper.instance.getTransaksiByBulan(bulan, tahun, search: search);
    setState(() { data = d; loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final tahunList = List.generate(6, (i) => DateTime.now().year - 3 + i);
    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: bulan,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(bulanNama[i + 1]))),
                    onChanged: (v) { setState(() => bulan = v!); _load(); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: tahun,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: tahunList.map((t) => DropdownMenuItem(value: t, child: Text('$t'))).toList(),
                    onChanged: (v) { setState(() => tahun = v!); _load(); },
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) { search = v; _load(); },
                decoration: const InputDecoration(hintText: 'Cari asal, motor, barang...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text('Total ${data.length} Transaksi', style: const TextStyle(color: Colors.grey))),
            ]),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : data.isEmpty
                    ? const Center(child: Text('Belum ada transaksi bulan ini'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: data.length,
                        itemBuilder: (_, i) => _card(data[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> t) {
    final status = (t['status'] ?? 'pending') as String;
    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderFormPage(orderId: t['id'])));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('#${t['no_transaksi'] ?? '-'}', style: TextStyle(color: AppColors.biruTua, fontWeight: FontWeight.bold)),
              Text(t['tanggal'] ?? '-', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            _baris('Asal', t['asal']),
            _baris('Motor', t['motor']),
            _baris('Barang', t['daftar_barang']),
            _baris('Proses', t['proses']),
            _baris('Harga', formatRupiah(t['total_harga'])),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.statusBg(status), borderRadius: BorderRadius.circular(8)),
              child: Text(AppColors.statusLabel(status).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.statusText(status))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _baris(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
        Expanded(child: Text('${value ?? '-'}', style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}