import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database_helper.dart';
import '../app_theme.dart';

class OrderFormPage extends StatefulWidget {
  final int? orderId; // null = tambah baru, terisi = edit
  const OrderFormPage({super.key, this.orderId});
  @override
  State<OrderFormPage> createState() => _OrderFormPageState();
}

class _OrderFormPageState extends State<OrderFormPage> {
  String noTransaksi = '';
  DateTime tanggal = DateTime.now();
  final _asal = TextEditingController();
  String? motor;
  String? proses;
  String status = 'antre'; // order baru otomatis 'Antre' sesuai ketentuan

  List<Map<String, dynamic>> items = [];
  final _langgeng = TextEditingController();
  final _juki = TextEditingController();
  final _rio = TextEditingController();
  final _kas = TextEditingController();
  final _kasVapor = TextEditingController();
  final _kasMaintenance = TextEditingController();
  final _catatan = TextEditingController();

  List<Map<String, dynamic>> masterMotor = [];
  List<Map<String, dynamic>> masterProses = [];
  bool loading = true;
  bool saving = false;

  bool get isEdit => widget.orderId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    masterMotor = await DatabaseHelper.instance.getMaster('master_motor');
    masterProses = await DatabaseHelper.instance.getMaster('master_proses');

    if (isEdit) {
      final h = await DatabaseHelper.instance.getOrderHeader(widget.orderId!);
      final its = await DatabaseHelper.instance.getOrderItems(widget.orderId!);
      if (h != null) {
        noTransaksi = h['no_transaksi'] ?? '';
        tanggal = DateTime.tryParse(h['tanggal'] ?? '') ?? DateTime.now();
        _asal.text = h['asal'] ?? '';
        motor = h['motor'];
        proses = h['proses'];
        status = h['status'] ?? 'pending';
        _langgeng.text = formatRupiah(h['bagian_langgeng'], withRp: false);
        _juki.text = formatRupiah(h['bagian_juki'], withRp: false);
        _rio.text = formatRupiah(h['bagian_rio'], withRp: false);
        _kas.text = h['kas'] != null ? formatRupiah(h['kas'], withRp: false) : '';
        _kasVapor.text = h['kas_vapor'] != null ? formatRupiah(h['kas_vapor'], withRp: false) : '';
        _kasMaintenance.text = h['kas_maintenance'] != null ? formatRupiah(h['kas_maintenance'], withRp: false) : '';
        _catatan.text = h['catatan'] ?? '';
      }
      items = its;
    } else {
      noTransaksi = await DatabaseHelper.instance.generateNoTransaksi();
    }
    setState(() => loading = false);
  }

  double get totalHarga => items.fold(0.0, (sum, it) => sum + ((it['harga'] as num?)?.toDouble() ?? 0));

  Future<void> _pilihTanggal() async {
    final d = await showDatePicker(context: context, initialDate: tanggal, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) setState(() => tanggal = d);
  }

  Future<void> _tambahBarang({Map<String, dynamic>? existing, int? index}) async {
    final hasil = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TambahBarangSheet(existing: existing, motor: motor, proses: proses),
    );
    if (hasil != null) {
      setState(() {
        if (index != null) {
          items[index] = hasil;
        } else {
          items.add(hasil);
        }
      });
    }
  }

  Future<void> _simpan() async {
    if (_asal.text.trim().isEmpty || motor == null || proses == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama, Type, dan Proses wajib diisi')));
      return;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tambahkan minimal 1 barang')));
      return;
    }
    setState(() => saving = true);

    final header = {
      'no_transaksi': noTransaksi,
      'tanggal': tanggal.toIso8601String().substring(0, 10),
      'asal': _asal.text.trim(),
      'motor': motor,
      'proses': proses,
      'status': status,
      'harga': totalHarga,
      'bagian_langgeng': parseRupiah(_langgeng.text),
      'bagian_juki': parseRupiah(_juki.text),
      'bagian_rio': parseRupiah(_rio.text),
      'kas': _kas.text.isEmpty ? null : parseRupiah(_kas.text),
      'kas_vapor': _kasVapor.text.isEmpty ? null : parseRupiah(_kasVapor.text),
      'kas_maintenance': _kasMaintenance.text.isEmpty ? null : parseRupiah(_kasMaintenance.text),
      'catatan': _catatan.text.trim(),
    };

    if (isEdit) {
      await DatabaseHelper.instance.updateOrder(id: widget.orderId!, header: header, items: items);
    } else {
      await DatabaseHelper.instance.insertOrder(header: header, items: items);
    }

    setState(() => saving = false);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Order' : 'Buat Order Baru')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _cardWrapper('Informasi Order', [
            Row(children: [
              Expanded(child: _readonlyField('No ID Transaksi', noTransaksi)),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _pilihTanggal,
                  child: _readonlyField('Tanggal', '${tanggal.day}/${tanggal.month}/${tanggal.year}', icon: Icons.calendar_today),
                ),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          _cardWrapper('Detail Order', [
            TextField(controller: _asal, decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            _dropdownMaster('Type', motor, masterMotor, (v) => setState(() => motor = v), tableKey: 'master_motor'),
            const SizedBox(height: 12),
            _dropdownMaster('Proses', proses, masterProses, (v) => setState(() => proses = v), tableKey: 'master_proses'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'antre', child: Text('Antre')),
                DropdownMenuItem(value: 'proses', child: Text('On Proses')),
                DropdownMenuItem(value: 'selesai', child: Text('Selesai')),
              ],
              onChanged: (v) => setState(() => status = v ?? 'pending'),
            ),
          ]),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Daftar Barang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              TextButton.icon(onPressed: () => _tambahBarang(), icon: const Icon(Icons.add), label: const Text('Tambah Barang')),
            ],
          ),
          ...items.asMap().entries.map((e) {
            final i = e.key;
            final it = e.value;
            final qty = (it['qty'] as num?)?.toDouble() ?? 1;
            final qtyLabel = qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
            final satuan = (it['harga_satuan'] as num?)?.toDouble() ?? (it['harga'] as num?)?.toDouble() ?? 0;
            return Card(
              child: ListTile(
                title: Text(it['barang'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '$qtyLabel pcs × ${formatRupiah(satuan)}'
                  '${it['warna_cat'] != null && it['warna_cat'] != '' ? ' • ${it['warna_cat']}' : ''}'
                  '${it['warna_lis'] != null && it['warna_lis'] != '' ? ' • Lis ${it['warna_lis']}' : ''}',
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatRupiah(it['harga']), style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _tambahBarang(existing: it, index: i)),
                  IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => setState(() => items.removeAt(i))),
                ]),
              ),
            );
          }),
          if (items.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.biruTerang.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total Harga', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(formatRupiah(totalHarga), style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.biruTua, fontSize: 16)),
              ]),
            ),
          const SizedBox(height: 20),
          _cardWrapper('Pembagian', [
            Row(children: [
              Expanded(child: TextField(controller: _langgeng, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Langgeng', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _juki, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Juki', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _rio, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Rio', border: OutlineInputBorder()))),
            ]),
          ]),
          const SizedBox(height: 16),
          _cardWrapper('KAS (isi salah satu atau kosongkan semua)', [
            Row(children: [
              Expanded(child: TextField(controller: _kas, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'KAS', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _kasVapor, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'KAS Vapor', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _kasMaintenance, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'KAS Maintenance', border: OutlineInputBorder()))),
            ]),
          ]),
          const SizedBox(height: 16),
          TextField(controller: _catatan, decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder())),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Batal'))),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: saving ? null : _simpan,
                style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua, padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: saving ? const SizedBox() : const Icon(Icons.save),
                label: saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Simpan Order'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _cardWrapper(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _readonlyField(String label, String value, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(value, style: const TextStyle(fontSize: 14)),
          if (icon != null) Icon(icon, size: 16, color: Colors.grey),
        ]),
      ]),
    );
  }

  Widget _dropdownMaster(String label, String? value, List<Map<String, dynamic>> master, ValueChanged<String?> onChanged, {required String tableKey}) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.settings, size: 18),
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => MasterDataEditorPage(table: tableKey, title: label)));
            _load();
          },
        ),
      ),
      items: master.map((m) => DropdownMenuItem<String>(value: m['nama'] as String, child: Text(m['nama']))).toList(),
      onChanged: onChanged,
    );
  }
}

// ---------- MODAL TAMBAH/EDIT BARANG ----------

class _TambahBarangSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String? motor;
  final String? proses;
  const _TambahBarangSheet({this.existing, this.motor, this.proses});
  @override
  State<_TambahBarangSheet> createState() => _TambahBarangSheetState();
}

class _TambahBarangSheetState extends State<_TambahBarangSheet> {
  final _barang = TextEditingController();
  final _kode = TextEditingController();
  final _hargaManual = TextEditingController(); // harga satuan
  final _qty = TextEditingController(text: '1');
  String? warnaCat;
  String? warnaLis;
  bool pakaiHargaManual = false;
  double? hargaDariDaftar; // harga satuan dari daftar/riwayat
  List<Map<String, dynamic>> saran = [];
  bool _sudahDiketik = false; // true setelah user mengetik sesuatu (bukan sekadar edit item lama)
  List<Map<String, dynamic>> masterWarnaCat = [];
  List<Map<String, dynamic>> masterWarnaLis = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadMaster();
    if (widget.existing != null) {
      _barang.text = widget.existing!['barang'] ?? '';
      _kode.text = widget.existing!['kode'] ?? '';
      warnaCat = widget.existing!['warna_cat'];
      warnaLis = widget.existing!['warna_lis'];
      final qtyLama = (widget.existing!['qty'] as num?)?.toDouble() ?? 1;
      _qty.text = qtyLama == qtyLama.roundToDouble() ? qtyLama.toInt().toString() : qtyLama.toString();
      final satuanLama = (widget.existing!['harga_satuan'] as num?)?.toDouble() ?? (widget.existing!['harga'] as num?)?.toDouble();
      _hargaManual.text = formatRupiah(satuanLama, withRp: false);
      pakaiHargaManual = true;
    }
  }

  double get _qtyValue => double.tryParse(_qty.text.replaceAll(',', '.')) ?? 0;
  double get _hargaSatuanAktif => pakaiHargaManual ? parseRupiah(_hargaManual.text) : (hargaDariDaftar ?? 0);
  double get _subtotal => _qtyValue * _hargaSatuanAktif;

  Future<void> _loadMaster() async {
    masterWarnaCat = await DatabaseHelper.instance.getMaster('master_warna_cat');
    masterWarnaLis = await DatabaseHelper.instance.getMaster('master_warna_lis');
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _cari(String q) {
    _sudahDiketik = true;
    if (q.length < 2) {
      _debounce?.cancel();
      setState(() => saran = []);
      return;
    }
    // Autocomplete sebelumnya query DB di setiap huruf yang diketik.
    // Di-debounce 300ms supaya tidak query berlebihan saat mengetik cepat.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final hasil = await DatabaseHelper.instance.cariBarang(q);
      if (mounted) setState(() => saran = hasil);
    });
  }

  Future<void> _pilihSaran(Map<String, dynamic> s) async {
    final nama = s['nama_barang'] as String;
    // Prioritas harga otomatis: kombinasi Type Motor + Barang + Proses.
    // Kalau kombinasi itu belum pernah dipakai, fallback ke harga_terakhir
    // per-nama-barang saja (katalog_barang), seperti sebelumnya.
    final hargaKombinasi = await DatabaseHelper.instance.cariHargaKombinasi(
      widget.motor ?? '', nama, widget.proses ?? '',
    );
    setState(() {
      _barang.text = nama;
      hargaDariDaftar = hargaKombinasi ?? (s['harga_terakhir'] as num?)?.toDouble();
      pakaiHargaManual = hargaDariDaftar == null;
      saran = [];
    });
  }

  Future<void> _simpan() async {
    if (_barang.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama barang wajib diisi')));
      return;
    }
    if (_qtyValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Qty harus lebih dari 0')));
      return;
    }
    final hargaSatuan = _hargaSatuanAktif;
    if (hargaSatuan <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi harga satuan terlebih dahulu')));
      return;
    }
    // Simpan/perbarui katalog barang (untuk autocomplete nama) supaya
    // harga_terakhir selalu yang terbaru...
    await DatabaseHelper.instance.insertOrUpdateKatalogBarang(_barang.text.trim(), hargaSatuan);
    // ...dan simpan/perbarui harga per KOMBINASI Type Motor + Barang + Proses
    // (dasar utama harga otomatis). Histori harga lama otomatis tersimpan di
    // dalam method ini, tidak pernah dihapus.
    await DatabaseHelper.instance.insertOrUpdateHargaKombinasi(
      widget.motor ?? '', _barang.text.trim(), widget.proses ?? '', hargaSatuan,
    );
    Navigator.pop(context, {
      'barang': _barang.text.trim(),
      'kode': _kode.text.trim(),
      'warna_cat': warnaCat,
      'warna_lis': warnaLis,
      'qty': _qtyValue,
      'harga_satuan': hargaSatuan,
      'harga': _subtotal, // subtotal = qty x harga satuan
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Tambah / Edit Barang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          TextField(
            controller: _barang,
            onChanged: _cari,
            decoration: const InputDecoration(labelText: 'Barang / Part', border: OutlineInputBorder()),
          ),
          if (saran.isNotEmpty || (_sudahDiketik && _barang.text.trim().isNotEmpty))
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  ...saran.map((s) => ListTile(
                    dense: true,
                    title: Text(s['nama_barang']),
                    trailing: Text(s['harga_terakhir'] != null ? formatRupiah(s['harga_terakhir']) : '-'),
                    onTap: () => _pilihSaran(s),
                  )),
                  // Kalau nama yang diketik belum ada persis di katalog, tawarkan
                  // opsi eksplisit untuk menambahkannya sebagai barang baru.
                  // Barang baru ini langsung bisa dipakai di transaksi (tersimpan
                  // ke katalog_barang begitu form barang disimpan).
                  if (_barang.text.trim().isNotEmpty &&
                      !saran.any((s) => (s['nama_barang'] as String).toLowerCase() == _barang.text.trim().toLowerCase()))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add_circle_outline, size: 18, color: AppColors.biruTua),
                      title: Text('Tambah Barang Baru: "${_barang.text.trim()}"', style: const TextStyle(color: AppColors.biruTua, fontWeight: FontWeight.w600)),
                      onTap: () => setState(() {
                        // Nama sudah terisi dari yang diketik user; cukup tutup
                        // daftar saran, lanjut isi harga & qty manual di bawah.
                        hargaDariDaftar = null;
                        pakaiHargaManual = true;
                        saran = [];
                      }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(controller: _kode, decoration: const InputDecoration(labelText: 'Kode (opsional)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: warnaCat,
            decoration: const InputDecoration(labelText: 'Warna Cat (opsional, kosongkan jika Vapor saja)', border: OutlineInputBorder()),
            items: masterWarnaCat.map((m) => DropdownMenuItem<String>(value: m['nama'] as String, child: Text(m['nama']))).toList(),
            onChanged: (v) => setState(() => warnaCat = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: warnaLis,
            decoration: const InputDecoration(labelText: 'Warna Lis (opsional)', border: OutlineInputBorder()),
            items: masterWarnaLis.map((m) => DropdownMenuItem<String>(value: m['nama'] as String, child: Text(m['nama']))).toList(),
            onChanged: (v) => setState(() => warnaLis = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Qty', border: OutlineInputBorder(), suffixText: 'pcs'),
          ),
          const SizedBox(height: 12),
          RadioListTile<bool>(
            value: false,
            groupValue: pakaiHargaManual,
            title: Text('Harga satuan dari daftar${hargaDariDaftar != null ? ' (${formatRupiah(hargaDariDaftar)})' : ''}'),
            onChanged: hargaDariDaftar == null ? null : (v) => setState(() => pakaiHargaManual = v!),
          ),
          RadioListTile<bool>(
            value: true,
            groupValue: pakaiHargaManual,
            title: const Text('Isi harga satuan manual'),
            onChanged: (v) => setState(() => pakaiHargaManual = v!),
          ),
          if (pakaiHargaManual)
            TextField(
              controller: _hargaManual,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Harga Satuan', border: OutlineInputBorder()),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.biruTerang.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Subtotal', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(formatRupiah(_subtotal), style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.biruTua, fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _simpan, style: FilledButton.styleFrom(backgroundColor: AppColors.biruTua, minimumSize: const Size(double.infinity, 48)), child: const Text('Simpan Barang')),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

// ---------- CRUD MASTER DATA (untuk tombol setting di dropdown) ----------

class MasterDataEditorPage extends StatefulWidget {
  final String table;
  final String title;
  const MasterDataEditorPage({super.key, required this.table, required this.title});
  @override
  State<MasterDataEditorPage> createState() => _MasterDataEditorPageState();
}

class _MasterDataEditorPageState extends State<MasterDataEditorPage> {
  List<Map<String, dynamic>> data = [];
  bool tampilkanNonaktif = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    data = await DatabaseHelper.instance.getMaster(widget.table, termasukNonaktif: tampilkanNonaktif);
    setState(() {});
  }

  Future<void> _tambahEditDialog({Map<String, dynamic>? existing}) async {
    final c = TextEditingController(text: existing?['nama'] ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Tambah ${widget.title}' : 'Edit ${widget.title}'),
        content: TextField(controller: c, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              if (c.text.trim().isEmpty) return;
              if (existing == null) {
                await DatabaseHelper.instance.insertMaster(widget.table, c.text.trim());
              } else {
                await DatabaseHelper.instance.updateMaster(widget.table, existing['id'], c.text.trim());
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
        title: const Text('Hapus data ini?'),
        content: Text('Kalau "${d['nama']}" sudah pernah dipakai di transaksi, data tidak akan dihapus permanen — hanya dinonaktifkan supaya transaksi lama tetap aman.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lanjutkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final dihapusPermanen = await DatabaseHelper.instance.deleteMaster(widget.table, d['id']);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dihapusPermanen ? '"${d['nama']}" dihapus' : '"${d['nama']}" dinonaktifkan (sudah dipakai di transaksi)'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Kelola ${widget.title}'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _tambahEditDialog())],
      ),
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
                title: Text(d['nama'], style: TextStyle(color: aktif ? Colors.black : Colors.grey)),
                subtitle: aktif ? null : const Text('Nonaktif', style: TextStyle(color: Colors.orange, fontSize: 11)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(
                    value: aktif,
                    onChanged: (v) async {
                      await DatabaseHelper.instance.toggleAktifMaster(widget.table, d['id'], v);
                      _load();
                    },
                  ),
                  IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _tambahEditDialog(existing: d)),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    onPressed: () => _hapus(d),
                  ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}