const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

String formatBytes(num bytes) {
  if (bytes >= 1000000000) {
    return '${(bytes / 1000000000).toStringAsFixed(2).replaceAll('.', ',')} GB';
  }
  return '${(bytes / 1000000).toStringAsFixed(2).replaceAll('.', ',')} MB';
}

String formatDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';
