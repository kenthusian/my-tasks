import 'package:flutter/material.dart';

const priorityLabels = ['Low', 'Medium', 'High'];
const repeatLabels = ['Never', 'Daily', 'Weekly', 'Monthly'];
const priorityColors = [Colors.green, Colors.orange, Colors.red];

// Palette from the design mockups (indigo / slate, amber for "saved offline").
const indigo = Color(0xFF4F46E5);
const rose = Color(0xFFE11D48);
const amber = Color(0xFFD97706);
const emerald = Color(0xFF059669);
const slate50 = Color(0xFFF8FAFC);
const slate100 = Color(0xFFF1F5F9);
const slate200 = Color(0xFFE2E8F0);
const slate400 = Color(0xFF94A3B8);
const slate500 = Color(0xFF64748B);
const slate900 = Color(0xFF0F172A);

String formatDue(int ms) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, $hh:$mm';
}

String formatClock(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}
