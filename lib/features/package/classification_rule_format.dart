// Label tampilan untuk aturan klasifikasi. Hanya memformat data model yang
// sudah ada; tidak ada aturan bisnis baru di sini.

const _dayLabels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// Bit ke-n pada daysOfWeekMask mewakili hari ke-n, bit 0 = Senin.
String classificationRuleDayLabel(int mask) {
  if (mask == 127) return 'Setiap hari';

  final days = <String>[
    for (var index = 0; index < _dayLabels.length; index++)
      if ((mask & (1 << index)) != 0) _dayLabels[index],
  ];

  return days.isEmpty ? 'Tidak ada hari' : days.join(', ');
}

String classificationRuleAppLabel(String? appPackageName) {
  final app = appPackageName?.trim() ?? '';
  return app.isEmpty ? 'Semua aplikasi' : app;
}

String classificationRuleTimeLabel(int? startMinute, int? endMinute) {
  if (startMinute == null || endMinute == null) return 'Sepanjang hari';
  return '${classificationRuleClockLabel(startMinute)} - '
      '${classificationRuleClockLabel(endMinute)}';
}

/// Nama satu hari, indeks 0 = Senin.
String classificationRuleDayName(int index) => _dayLabels[index];

/// Satu menit ke jam 'HH:MM'. 1440 tampil sebagai 24:00 (hingga akhir hari).
String classificationRuleClockLabel(int minute) {
  final hour = minute ~/ 60;
  final rest = minute % 60;

  return '${hour.toString().padLeft(2, '0')}:'
      '${rest.toString().padLeft(2, '0')}';
}
