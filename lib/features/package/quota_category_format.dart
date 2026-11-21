import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'package_format.dart';

String quotaCategoryTypeLabel(QuotaCategoryType type) => switch (type) {
  QuotaCategoryType.main => 'Kuota Utama',
  QuotaCategoryType.night => 'Kuota Malam',
  QuotaCategoryType.social => 'Kuota Sosial',
  QuotaCategoryType.appSpecific => 'Kuota Aplikasi',
  QuotaCategoryType.custom => 'Kategori Khusus',
};

IconData quotaCategoryTypeIcon(QuotaCategoryType type) => switch (type) {
  QuotaCategoryType.main => Icons.public,
  QuotaCategoryType.night => Icons.nightlight_outlined,
  QuotaCategoryType.social => Icons.forum_outlined,
  QuotaCategoryType.appSpecific => Icons.apps,
  QuotaCategoryType.custom => Icons.extension_outlined,
};

/// Ringkasan masa berlaku kategori untuk ditampilkan di daftar.
String quotaCategoryValidityLabel(QuotaCategory category) {
  final from = category.validFrom;
  final until = category.validUntil;

  if (from == null && until == null) return 'Selalu berlaku';
  if (from != null && until != null) {
    return '${formatDate(from)} - ${formatDate(until)}';
  }
  if (from != null) return 'Mulai ${formatDate(from)}';
  return 'Sampai ${formatDate(until!)}';
}
