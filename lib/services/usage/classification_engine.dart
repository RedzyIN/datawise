// Usage Classification Engine: logika MURNI tanpa database, Flutter UI,
// Provider, atau Android MethodChannel.
//
// Bit ke-n pada daysOfWeekMask mewakili hari ke-n, dengan bit 0 = Senin ...
// bit 6 = Minggu. Urutan ini mengikuti DateTime.weekday - 1.
import '../../models/models.dart';

/// Bit mask untuk satu hari. [weekday] memakai nilai [DateTime.weekday].
int dayOfWeekMaskBit(int weekday) => 1 << (weekday - 1);

enum ClassificationOutcome { matchedRule, mainFallback, unclassified }

/// Alasan hasil UNCLASSIFIED. Dibedakan agar konfigurasi aturan yang rusak
/// tidak tersamarkan sebagai "tidak ada aturan".
enum UnclassifiedReason {
  /// Tidak ada aturan yang cocok dan tidak ada kategori MAIN yang valid.
  noValidCategory,

  /// Ada aturan yang cocok, tetapi kategori tujuannya disabled, tidak berlaku,
  /// atau bukan milik paket catatan pemakaian.
  matchedRuleInvalidCategory,
}

class ClassificationResult {
  const ClassificationResult._({
    required this.outcome,
    this.matchedRule,
    this.category,
    this.unclassifiedReason,
  });

  const ClassificationResult.rule(
    ClassificationRule rule,
    QuotaCategory category,
  ) : this._(
        outcome: ClassificationOutcome.matchedRule,
        matchedRule: rule,
        category: category,
      );

  const ClassificationResult.main(QuotaCategory category)
    : this._(outcome: ClassificationOutcome.mainFallback, category: category);

  const ClassificationResult.unclassified(
    UnclassifiedReason reason, {
    ClassificationRule? rule,
  }) : this._(
         outcome: ClassificationOutcome.unclassified,
         unclassifiedReason: reason,
         matchedRule: rule,
       );

  final ClassificationOutcome outcome;

  /// Aturan pemenang. Tetap diisi saat aturan cocok tetapi kategorinya tidak
  /// valid, supaya pemanggil bisa melaporkan konfigurasi yang bermasalah.
  final ClassificationRule? matchedRule;

  /// Kategori tujuan yang sudah tervalidasi; null untuk UNCLASSIFIED.
  final QuotaCategory? category;

  final UnclassifiedReason? unclassifiedReason;

  bool get isClassified => outcome != ClassificationOutcome.unclassified;
}

class ClassificationEngine {
  const ClassificationEngine();

  /// Menentukan hasil klasifikasi untuk [record] berdasarkan [rules] dan
  /// [categories] yang diberikan. Kedua daftar boleh berisi data paket lain;
  /// engine hanya memakai aturan dan kategori milik [UsageRecord.packageId].
  ClassificationResult classify({
    required UsageRecord record,
    required List<ClassificationRule> rules,
    required List<QuotaCategory> categories,
  }) {
    // Aturan waktu pengguna mengikuti waktu setempat perangkat.
    final startedAt = record.periodStartAt.toLocal();

    final categoryById = <String, QuotaCategory>{
      for (final category in categories)
        if (category.id != null && category.packageId == record.packageId)
          category.id!: category,
    };

    final candidates = rules.where((rule) {
      if (!rule.isEnabled) return false;
      // Aturan hanya boleh dipakai bila kategorinya milik paket yang sama.
      if (!categoryById.containsKey(rule.quotaCategoryId)) return false;
      if (!_matchesApp(rule, record)) return false;
      return _matchesTime(rule, startedAt);
    }).toList();

    // Urutan deterministik: priority terbesar, aturan spesifik aplikasi
    // mengalahkan wildcard, lalu ID sebagai penentu akhir.
    candidates.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;

      final aSpecific = a.appPackageName == null ? 1 : 0;
      final bSpecific = b.appPackageName == null ? 1 : 0;
      if (aSpecific != bSpecific) return aSpecific.compareTo(bSpecific);

      return (a.id ?? '').compareTo(b.id ?? '');
    });

    if (candidates.isNotEmpty) {
      final rule = candidates.first;
      final category = categoryById[rule.quotaCategoryId]!;

      // Integritas data: aturan yang menang tetapi kategorinya tidak valid
      // menjadi UNCLASSIFIED. Tidak ada aturan lain dan tidak ada fallback
      // MAIN yang dipakai diam-diam.
      if (!_isCategoryActive(category, startedAt)) {
        return ClassificationResult.unclassified(
          UnclassifiedReason.matchedRuleInvalidCategory,
          rule: rule,
        );
      }

      return ClassificationResult.rule(rule, category);
    }

    final main = _findMainCategory(categoryById.values, startedAt);
    if (main == null) {
      return const ClassificationResult.unclassified(
        UnclassifiedReason.noValidCategory,
      );
    }

    return ClassificationResult.main(main);
  }

  bool _matchesApp(ClassificationRule rule, UsageRecord record) {
    final target = rule.appPackageName;
    if (target == null) return true;
    return target == record.appPackageName;
  }

  bool _matchesTime(ClassificationRule rule, DateTime localStart) {
    final start = rule.startMinute;
    final end = rule.endMinute;

    // Tanpa batasan jam: hari tetap diperiksa lewat daysOfWeekMask.
    if (start == null && end == null) {
      return _matchesDay(rule.daysOfWeekMask, localStart.weekday);
    }

    // Repository menolak salah satu null, tetapi data rusak tidak boleh cocok.
    if (start == null || end == null) return false;

    final minute = localStart.hour * 60 + localStart.minute;

    // Interval normal [start, end). endMinute = 1440 berarti hingga akhir hari.
    if (start < end) {
      return minute >= start &&
          minute < end &&
          _matchesDay(rule.daysOfWeekMask, localStart.weekday);
    }

    // Lintas tengah malam: hari yang diperiksa adalah hari interval dimulai.
    if (start > end) {
      if (minute >= start) {
        return _matchesDay(rule.daysOfWeekMask, localStart.weekday);
      }
      if (minute < end) {
        return _matchesDay(rule.daysOfWeekMask, _previousWeekday(localStart));
      }
      return false;
    }

    // start == end adalah interval kosong pada rentang setengah terbuka.
    return false;
  }

  int _previousWeekday(DateTime local) =>
      local.weekday == DateTime.monday ? DateTime.sunday : local.weekday - 1;

  bool _matchesDay(int mask, int weekday) =>
      (mask & dayOfWeekMaskBit(weekday)) != 0;

  bool _isCategoryActive(QuotaCategory category, DateTime localStart) {
    if (!category.isEnabled) return false;

    final day = dateOnly(localStart);
    if (category.validFrom != null &&
        day.isBefore(dateOnly(category.validFrom!))) {
      return false;
    }
    if (category.validUntil != null &&
        day.isAfter(dateOnly(category.validUntil!))) {
      return false;
    }

    return true;
  }

  QuotaCategory? _findMainCategory(
    Iterable<QuotaCategory> categories,
    DateTime localStart,
  ) {
    final candidates = categories
        .where(
          (category) =>
              category.categoryType == QuotaCategoryType.main &&
              _isCategoryActive(category, localStart),
        )
        .toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => (a.id ?? '').compareTo(b.id ?? ''));

    return candidates.first;
  }
}
