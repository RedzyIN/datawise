import 'dart:convert';

import 'package:flutter/services.dart';

/// Sumber ikon aplikasi untuk rincian pemakaian.
///
/// Ikon berasal dari Android `PackageManager.getApplicationIcon(packageName)`
/// lewat MethodChannel `datawise/usage` (method `getAppIcons`), bukan dari
/// internet, emoji, atau tebakan berdasarkan nama aplikasi.
abstract class AppIconService {
  Future<Map<String, Uint8List>> load(Iterable<String> packageNames);
}

class PlatformAppIconService implements AppIconService {
  static const MethodChannel _channel = MethodChannel('datawise/usage');

  /// Satu permintaan dibatasi agar payload MethodChannel tetap kecil.
  static const int _maxPerRequest = 40;

  @override
  Future<Map<String, Uint8List>> load(Iterable<String> packageNames) async {
    final names = <String>{
      for (final name in packageNames)
        if (name.isNotEmpty) name,
    }.toList();

    final icons = <String, Uint8List>{};
    if (names.isEmpty) return icons;

    for (var start = 0; start < names.length; start += _maxPerRequest) {
      final end = start + _maxPerRequest > names.length
          ? names.length
          : start + _maxPerRequest;

      try {
        final result = await _channel.invokeMapMethod<String, dynamic>(
          'getAppIcons',
          {'packageNames': names.sublist(start, end)},
        );
        if (result == null) continue;

        for (final entry in result.entries) {
          final encoded = entry.value;
          if (encoded is! String || encoded.isEmpty) continue;

          try {
            icons[entry.key] = base64Decode(encoded);
          } catch (_) {
            // Ikon rusak diabaikan; UI memakai ikon fallback DATAWISE.
          }
        }
      } on MissingPluginException {
        // Platform tanpa channel Android (desktop/pengujian): tanpa ikon.
        return icons;
      } on PlatformException {
        continue;
      }
    }

    return icons;
  }
}
