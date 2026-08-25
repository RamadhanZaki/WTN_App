import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const hitamLogo = Color(0xFF0B0F14);
  static const biruTua = Color(0xFF1976D2);
  static const biruTerang = Color(0xFF2E9FE8);

  static Color statusBg(String status) {
    switch (status) {
      case 'pending': return const Color(0xFFFAEEDA);
      case 'antre': return const Color(0xFFEEE5F9);
      case 'proses': return const Color(0xFFE6F1FB);
      case 'selesai': return const Color(0xFFEAF3DE);
      default: return const Color(0xFFF1EFE8);
    }
  }

  static Color statusText(String status) {
    switch (status) {
      case 'pending': return const Color(0xFF854F0B);
      case 'antre': return const Color(0xFF6A3FA0);
      case 'proses': return const Color(0xFF185FA5);
      case 'selesai': return const Color(0xFF27500A);
      default: return const Color(0xFF444441);
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'pending': return 'Pending';
      case 'antre': return 'Antre';
      case 'proses': return 'On Proses';
      case 'selesai': return 'Selesai';
      default: return 'Pending';
    }
  }
}

String formatRupiah(dynamic value, {bool withRp = true}) {
  final n = (value ?? 0) is num ? (value as num) : (double.tryParse(value.toString()) ?? 0);
  final s = n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return withRp ? 'Rp$s' : s;
}

// TextInputFormatter: otomatis kasih titik ribuan saat mengetik angka
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final n = int.parse(digits);
    final formatted = n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

double parseRupiah(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? 0 : double.parse(digits);
}