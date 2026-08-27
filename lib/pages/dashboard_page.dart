import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';
import 'transaksi_page.dart';
import 'detail_transaksi_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic> ringkasan = {};
  List<Map<String, dynamic>> grafik = [];
  List<Map<String, dynamic>> terbaru = [];
  bool loading = true;
  int periodeBulan = 6;
  String tipeGrafik = 'garis'; // 'garis' atau 'batang'
  int bulanRingkasan = DateTime.now().month;
  int tahunRingkasan = DateTime.now().year;

  final bulanNama = const ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    // Keempat query ini independen satu sama lain, jadi dijalankan paralel
    // dengan Future.wait alih-alih menunggu satu-satu (await berurutan)
    // seperti sebelumnya — total waktu loading dashboard jadi jauh lebih cepat.
    final results = await Future.wait([
      DatabaseHelper.instance.getRingkasanBulanIni(bulan: bulanRingkasan, tahun: tahunRingkasan),
      DatabaseHelper.instance.getGrafikOmzet(periodeBulan),
      DatabaseHelper.instance.getOrderTerbaru(limit: 10),
      DatabaseHelper.instance.getPengaturan('grafik_omset_tipe', defaultValue: 'garis'),
    ]);
    setState(() {
      ringkasan = results[0] as Map<String, dynamic>;
      grafik = (results[1] as List<Map<String, dynamic>>).reversed.toList();
      terbaru = results[2] as List<Map<String, dynamic>>;
      tipeGrafik = results[3] as String;
      loading = false;
    });
  }

  Future<void> _gantiPeriode(int bulan) async {
    setState(() => periodeBulan = bulan);
    final g = await DatabaseHelper.instance.getGrafikOmzet(bulan);
    setState(() => grafik = g.reversed.toList());
  }

  Future<void> _pilihPeriodeRingkasan() async {
    int tempBulan = bulanRingkasan;
    int tempTahun = tahunRingkasan;
    final tahunList = List.generate(6, (i) => DateTime.now().year - 3 + i);

    final hasil = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Pilih Bulan & Tahun'),
          content: Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: tempBulan,
                decoration: const InputDecoration(labelText: 'Bulan', isDense: true),
                items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(bulanNama[i + 1]))),
                onChanged: (v) => setDialogState(() => tempBulan = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: tempTahun,
                decoration: const InputDecoration(labelText: 'Tahun', isDense: true),
                items: tahunList.map((t) => DropdownMenuItem(value: t, child: Text('$t'))).toList(),
                onChanged: (v) => setDialogState(() => tempTahun = v!),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {'bulan': tempBulan, 'tahun': tempTahun}),
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );

    if (hasil != null) {
      setState(() {
        bulanRingkasan = hasil['bulan']!;
        tahunRingkasan = hasil['tahun']!;
      });
      final r = await DatabaseHelper.instance.getRingkasanBulanIni(bulan: bulanRingkasan, tahun: tahunRingkasan);
      setState(() => ringkasan = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        scrolledUnderElevation: 0,
        title: Transform.translate(
          // Logo dinaikkan 1 tingkat (sebelumnya sejajar center toolbar,
          // sekarang digeser ke atas) supaya tidak terlalu turun/mepet
          // ke tengah AppBar.
          offset: const Offset(0, -8),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/logo.png', height: 50, fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('MANAGEMENT SYSTEM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _omzetCard(),
                  const SizedBox(height: 20),
                  _grafikCard(),
                  const SizedBox(height: 20),
                  _ringkasanSection(),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Orderan Terbaru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransaksiPage())), child: const Text('Lihat Semua')),
                  ]),
                  Text('Menampilkan ${terbaru.length} transaksi terbaru', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  ...terbaru.map(_orderTile),
                ],
              ),
            ),
    );
  }

  Widget _omzetCard() {
    final langgeng = (ringkasan['langgeng'] as num?) ?? 0;
    final juki = (ringkasan['juki'] as num?) ?? 0;
    final rio = (ringkasan['rio'] as num?) ?? 0;

    final bagian = <Widget>[];
    if (langgeng > 0) bagian.add(_miniStat('Langgeng', langgeng));
    if (juki > 0) bagian.add(_miniStat('Juki', juki));
    if (rio > 0) bagian.add(_miniStat('Rio', rio));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.hitamLogo, Color(0xFF122531)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.biruTerang.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text('Omset Bulan ${bulanNama[bulanRingkasan]} $tahunRingkasan', style: TextStyle(color: AppColors.biruTerang.withOpacity(0.85), fontSize: 13)),
          ),
          InkWell(
            onTap: _pilihPeriodeRingkasan,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: AppColors.biruTerang.withOpacity(0.4)), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_month, size: 14, color: AppColors.biruTerang),
                const SizedBox(width: 4),
                Text('Ganti', style: TextStyle(fontSize: 12, color: AppColors.biruTerang)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(formatRupiah(ringkasan['omzet']), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        if (bagian.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [for (int i = 0; i < bagian.length; i++) ...[if (i > 0) const SizedBox(width: 12), bagian[i]]]),
        ],
      ]),
    );
  }

  Widget _miniStat(String label, num value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: AppColors.biruTerang.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.biruTerang.withOpacity(0.7), fontSize: 11)),
          Text(formatRupiah(value), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _grafikCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Row(children: [Icon(Icons.show_chart, size: 18, color: AppColors.biruTua), SizedBox(width: 6), Text('Grafik Omset', style: TextStyle(fontWeight: FontWeight.w600))]),
          PopupMenuButton<int>(
            initialValue: periodeBulan,
            onSelected: _gantiPeriode,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 3, child: Text('3 Bulan Terakhir')),
              PopupMenuItem(value: 6, child: Text('6 Bulan Terakhir')),
              PopupMenuItem(value: 12, child: Text('12 Bulan Terakhir')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('$periodeBulan Bulan Terakhir', style: const TextStyle(fontSize: 12)),
                const Icon(Icons.arrow_drop_down, size: 18),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        grafik.isEmpty
            ? const SizedBox(height: 140, child: Center(child: Text('Belum ada data', style: TextStyle(color: Colors.grey))))
            : SizedBox(
                height: 160,
                child: tipeGrafik == 'batang'
                    ? _BarChart(data: grafik, bulanNama: bulanNama)
                    : _LineChart(data: grafik, bulanNama: bulanNama),
              ),
      ]),
    );
  }

  Widget _ringkasanSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.bar_chart, size: 18, color: AppColors.biruTua), SizedBox(width: 6), Text('Ringkasan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _ringkasanTile('Total Transaksi Bulan Ini', ringkasan['total_transaksi'] ?? 0, Icons.calendar_month, AppColors.biruTua)),
        const SizedBox(width: 10),
        Expanded(child: _ringkasanTile('Transaksi Selesai', ringkasan['selesai'] ?? 0, Icons.check_circle, const Color(0xFF27500A))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _ringkasanTile('Transaksi On Proses', ringkasan['proses'] ?? 0, Icons.access_time, const Color(0xFF854F0B))),
        const SizedBox(width: 10),
        Expanded(child: _ringkasanTile('Transaksi Antre', ringkasan['antre'] ?? 0, Icons.hourglass_empty, const Color(0xFF6A3FA0))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _ringkasanTile('Belum Diambil', ringkasan['belum_diambil'] ?? 0, Icons.inventory_2, const Color(0xFFB5541B))),
        const SizedBox(width: 10),
        Expanded(child: _ringkasanTile('Piutang', ringkasan['piutang'] ?? 0, Icons.receipt_long, const Color(0xFFB02A2A), isRupiah: true)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _ringkasanTile('Pengeluaran', ringkasan['pengeluaran'] ?? 0, Icons.trending_down, const Color(0xFF6A3FA0), isRupiah: true)),
        const SizedBox(width: 10),
        Expanded(child: _ringkasanTile('Laba Bersih', ringkasan['laba_bersih'] ?? 0, Icons.savings, const Color(0xFF1B7A3D), isRupiah: true)),
      ]),
    ]);
  }

  Widget _ringkasanTile(String label, dynamic value, IconData icon, Color color, {bool isRupiah = false}) {
    final teks = isRupiah ? formatRupiah(value) : '$value';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Row(children: [
          CircleAvatar(radius: 18, backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(teks, style: TextStyle(fontSize: isRupiah ? 14 : 20, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ]),
    );
  }

  Widget _orderTile(Map<String, dynamic> t) {
    final status = (t['status'] ?? 'pending') as String;
    final statusAmbil = (t['status_pengambilan'] ?? 'belum_diambil') as String;
    final statusBayar = (t['status_pembayaran'] ?? 'belum_bayar') as String;
    final lis = (t['daftar_warna_lis'] ?? '').toString();
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: AppColors.hitamLogo, child: Icon(Icons.two_wheeler, color: AppColors.biruTerang, size: 18)),
        title: Text('#${t['no_transaksi'] ?? '-'}  ${t['asal'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Text('Type: ${t['motor'] ?? '-'}', style: const TextStyle(fontSize: 12)),
          Text('Warna: ${t['daftar_warna_cat'] ?? '-'}', style: const TextStyle(fontSize: 12)),
          if (lis.isNotEmpty) Text('Lis: $lis', style: const TextStyle(fontSize: 12)),
          Text('Proses: ${t['proses'] ?? '-'}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            _miniBadge(AppColors.statusLabel(status), AppColors.statusBg(status), AppColors.statusText(status)),
            _miniBadge(AppColors.ambilLabel(statusAmbil), AppColors.ambilBg(statusAmbil), AppColors.ambilText(statusAmbil)),
            _miniBadge(AppColors.bayarLabel(statusBayar), AppColors.bayarBg(statusBayar), AppColors.bayarText(statusBayar)),
          ]),
        ]),
        isThreeLine: true,
        trailing: Text(formatRupiah(t['total_harga']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailTransaksiPage(orderId: t['id'])));
          _load();
        },
      ),
    );
  }

  Widget _miniBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

// ---------- LINE CHART (custom painter, tanpa package tambahan) ----------

class _LineChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final List<String> bulanNama;
  const _LineChart({required this.data, required this.bulanNama});

  @override
  Widget build(BuildContext context) {
    final values = data.map((d) => ((d['omzet'] as num?) ?? 0).toDouble()).toList();
    final maxVal = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final labels = data.map((d) {
      final key = (d['bulan'] as String?) ?? '';
      final parts = key.split('-');
      return parts.length == 2 ? bulanNama[int.parse(parts[1])].substring(0, 3) : '-';
    }).toList();

    return CustomPaint(
      size: const Size(double.infinity, 160),
      painter: _LineChartPainter(values: values, labels: labels, maxVal: maxVal == 0 ? 1 : maxVal),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final double maxVal;
  _LineChartPainter({required this.values, required this.labels, required this.maxVal});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final chartHeight = size.height - 30;
    final stepX = values.length > 1 ? size.width / (values.length - 1) : size.width;

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = values.length > 1 ? i * stepX : size.width / 2;
      final y = chartHeight - (values[i] / maxVal) * (chartHeight - 20);
      points.add(Offset(x, y));
    }

    // Area fill
    final fillPath = Path()..moveTo(points.first.dx, chartHeight);
    for (final p in points) fillPath.lineTo(p.dx, p.dy);
    fillPath.lineTo(points.last.dx, chartHeight);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = const Color(0xFF1976D2).withOpacity(0.08));

    // Line
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) linePath.lineTo(p.dx, p.dy);
    canvas.drawPath(linePath, Paint()
      ..color = const Color(0xFF1976D2)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);

    // Dots + value labels
    final textStyle = TextStyle(color: Colors.grey.shade700, fontSize: 9);
    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4, Paint()..color = Colors.white);
      canvas.drawCircle(points[i], 4, Paint()..color = const Color(0xFF1976D2)..style = PaintingStyle.stroke..strokeWidth = 2);

      final tp = TextPainter(text: TextSpan(text: _formatSingkat(values[i]), style: textStyle), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(points[i].dx - tp.width / 2, points[i].dy - 18));

      final labelTp = TextPainter(text: TextSpan(text: labels[i], style: TextStyle(color: Colors.grey.shade600, fontSize: 10)), textDirection: TextDirection.ltr)..layout();
      labelTp.paint(canvas, Offset(points[i].dx - labelTp.width / 2, chartHeight + 8));
    }
  }

  String _formatSingkat(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}jt';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}rb';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}

// ---------- BAR CHART (custom painter, tanpa package tambahan) ----------

class _BarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final List<String> bulanNama;
  const _BarChart({required this.data, required this.bulanNama});

  @override
  Widget build(BuildContext context) {
    final values = data.map((d) => ((d['omzet'] as num?) ?? 0).toDouble()).toList();
    final maxVal = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final labels = data.map((d) {
      final key = (d['bulan'] as String?) ?? '';
      final parts = key.split('-');
      return parts.length == 2 ? bulanNama[int.parse(parts[1])].substring(0, 3) : '-';
    }).toList();

    return CustomPaint(
      size: const Size(double.infinity, 160),
      painter: _BarChartPainter(values: values, labels: labels, maxVal: maxVal == 0 ? 1 : maxVal),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final double maxVal;
  _BarChartPainter({required this.values, required this.labels, required this.maxVal});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final chartHeight = size.height - 30;
    final n = values.length;
    final slotWidth = size.width / n;
    final barWidth = (slotWidth * 0.9).clamp(16.0, 64.0);

    final barPaint = Paint()..color = const Color(0xFF1976D2);
    final textStyle = TextStyle(color: Colors.grey.shade700, fontSize: 9);
    final labelStyle = TextStyle(color: Colors.grey.shade600, fontSize: 10);

    for (int i = 0; i < n; i++) {
      final centerX = slotWidth * i + slotWidth / 2;
      final barHeight = maxVal == 0 ? 0.0 : (values[i] / maxVal) * (chartHeight - 20);
      final top = chartHeight - barHeight;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(centerX - barWidth / 2, top, barWidth, barHeight),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rect, barPaint);

      final tp = TextPainter(text: TextSpan(text: _formatSingkat(values[i]), style: textStyle), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(centerX - tp.width / 2, top - 16));

      final labelTp = TextPainter(text: TextSpan(text: labels[i], style: labelStyle), textDirection: TextDirection.ltr)..layout();
      labelTp.paint(canvas, Offset(centerX - labelTp.width / 2, chartHeight + 8));
    }
  }

  String _formatSingkat(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}jt';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}rb';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) => true;
}