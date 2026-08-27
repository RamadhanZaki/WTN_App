import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../app_theme.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});
  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  List<Map<String, dynamic>> data = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final d = await DatabaseHelper.instance.getAuditLog();
    setState(() { data = d; loading = false; });
  }

  String _formatWaktu(String iso) {
    try {
      final t = DateTime.parse(iso);
      final dd = t.day.toString().padLeft(2, '0');
      final mm = t.month.toString().padLeft(2, '0');
      final hh = t.hour.toString().padLeft(2, '0');
      final mi = t.minute.toString().padLeft(2, '0');
      return '$dd/$mm/${t.year}  $hh:$mi';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Aktivitas'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : data.isEmpty
              ? const Center(child: Text('Belum ada aktivitas tercatat', style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: data.length,
                    itemBuilder: (_, i) {
                      final d = data[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(radius: 16, backgroundColor: AppColors.biruTua.withOpacity(0.1), child: Icon(Icons.history, size: 16, color: AppColors.biruTua)),
                          title: Text(d['aksi'] ?? '-', style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${_formatWaktu(d['waktu'])}  •  ${d['aktor']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
