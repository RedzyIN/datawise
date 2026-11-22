import 'package:datawise/models/models.dart';
import 'package:datawise/services/usage/classification_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const packageId = 'pkg-1';
  const otherPackageId = 'pkg-2';
  const gb = 1000000000;

  // 16 November 2026 adalah hari Senin.
  final monday = DateTime(2026, 11, 16, 10);
  final tuesday = DateTime(2026, 11, 17, 10);
  const mondayBit = 1; // 1 << (DateTime.monday - 1)
  const tuesdayBit = 2; // 1 << (DateTime.tuesday - 1)

  const engine = ClassificationEngine();

  ClassificationRule rule({
    required String id,
    String categoryId = 'cat-night',
    String? app,
    int? start,
    int? end,
    int mask = 127,
    int priority = 0,
    bool enabled = true,
  }) {
    return ClassificationRule(
      id: id,
      quotaCategoryId: categoryId,
      ruleName: id,
      appPackageName: app,
      startMinute: start,
      endMinute: end,
      daysOfWeekMask: mask,
      priority: priority,
      isEnabled: enabled,
      createdAt: monday,
    );
  }

  QuotaCategory category({
    required String id,
    String package = packageId,
    QuotaCategoryType type = QuotaCategoryType.night,
    bool enabled = true,
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return QuotaCategory(
      id: id,
      packageId: package,
      categoryName: id,
      categoryType: type,
      capacityBytes: 5 * gb,
      validFrom: validFrom,
      validUntil: validUntil,
      isEnabled: enabled,
      createdAt: monday,
    );
  }

  QuotaCategory mainCategory({
    String id = 'cat-main',
    String package = packageId,
    bool enabled = true,
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return category(
      id: id,
      package: package,
      type: QuotaCategoryType.main,
      enabled: enabled,
      validFrom: validFrom,
      validUntil: validUntil,
    );
  }

  UsageRecord usage({
    String package = packageId,
    String? app = 'com.instagram.android',
    DateTime? at,
    int rx = 800,
    int tx = 200,
  }) {
    final start = at ?? monday;
    return UsageRecord(
      packageId: package,
      recordScope: app == null
          ? UsageRecordScope.deviceTotal
          : UsageRecordScope.appUsage,
      appPackageName: app,
      appName: 'Aplikasi',
      networkType: NetworkType.mobile,
      periodStartAt: start,
      periodEndAt: start.add(const Duration(minutes: 5)),
      rxBytes: rx,
      txBytes: tx,
      source: UsageSource.android,
      sourceKey: 'usage-${start.microsecondsSinceEpoch}-$app',
      recordedAt: start,
    );
  }

  ClassificationResult classify({
    required UsageRecord record,
    List<ClassificationRule> rules = const [],
    List<QuotaCategory> categories = const [],
  }) {
    return engine.classify(
      record: record,
      rules: rules,
      categories: categories,
    );
  }

  group('Pencocokan aturan', () {
    test('aturan spesifik Instagram cocok dengan penggunaan Instagram', () {
      final result = classify(
        record: usage(),
        rules: [rule(id: 'rule-1', app: 'com.instagram.android')],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.matchedRule);
      expect(result.matchedRule?.id, 'rule-1');
      expect(result.category?.id, 'cat-night');
    });

    test('aturan Instagram tidak cocok dengan aplikasi lain', () {
      final result = classify(
        record: usage(app: 'com.whatsapp'),
        rules: [rule(id: 'rule-1', app: 'com.instagram.android')],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
      expect(result.unclassifiedReason, UnclassifiedReason.noValidCategory);
    });

    test('aturan wildcard cocok dengan beberapa aplikasi', () {
      final rules = [rule(id: 'rule-1', app: null)];
      final categories = [category(id: 'cat-night')];

      final instagram = classify(
        record: usage(),
        rules: rules,
        categories: categories,
      );
      final whatsapp = classify(
        record: usage(app: 'com.whatsapp'),
        rules: rules,
        categories: categories,
      );

      expect(instagram.matchedRule?.id, 'rule-1');
      expect(whatsapp.matchedRule?.id, 'rule-1');
    });

    test('aturan yang dinonaktifkan tidak digunakan', () {
      final result = classify(
        record: usage(),
        rules: [
          rule(id: 'rule-1', app: 'com.instagram.android', enabled: false),
        ],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('priority 20 menang dibandingkan priority 10', () {
      final result = classify(
        record: usage(),
        rules: [
          rule(id: 'rule-10', priority: 10, categoryId: 'cat-a'),
          rule(id: 'rule-20', priority: 20, categoryId: 'cat-b'),
        ],
        categories: [
          category(id: 'cat-a'),
          category(id: 'cat-b'),
        ],
      );

      expect(result.matchedRule?.id, 'rule-20');
      expect(result.category?.id, 'cat-b');
    });

    test('aturan spesifik menang saat priority sama dengan wildcard', () {
      final result = classify(
        record: usage(),
        rules: [
          // ID wildcard lebih kecil, jadi ID saja akan memilih wildcard.
          rule(id: 'rule-a-wildcard', priority: 10, categoryId: 'cat-wildcard'),
          rule(
            id: 'rule-z-app',
            app: 'com.instagram.android',
            priority: 10,
            categoryId: 'cat-app',
          ),
        ],
        categories: [
          category(id: 'cat-wildcard'),
          category(id: 'cat-app'),
        ],
      );

      expect(result.matchedRule?.id, 'rule-z-app');
      expect(result.category?.id, 'cat-app');
    });

    test('hasil tetap sama meskipun urutan input aturan diubah', () {
      final rules = [
        rule(id: 'rule-b', priority: 5, categoryId: 'cat-b'),
        rule(id: 'rule-a', priority: 5, categoryId: 'cat-a'),
        rule(id: 'rule-c', app: 'com.instagram.android', priority: 5),
      ];
      final categories = [
        category(id: 'cat-a'),
        category(id: 'cat-b'),
        category(id: 'cat-night'),
      ];

      final forward = classify(
        record: usage(),
        rules: rules,
        categories: categories,
      );
      final backward = classify(
        record: usage(),
        rules: rules.reversed.toList(),
        categories: categories.reversed.toList(),
      );
      final shuffled = classify(
        record: usage(),
        rules: [rules[1], rules[2], rules[0]],
        categories: categories,
      );

      expect(forward.category?.id, 'cat-night');
      expect(backward.category?.id, forward.category?.id);
      expect(shuffled.category?.id, forward.category?.id);
      expect(backward.matchedRule?.id, forward.matchedRule?.id);
      expect(shuffled.matchedRule?.id, forward.matchedRule?.id);
    });
  });

  group('Pencocokan waktu', () {
    test('penggunaan di dalam rentang waktu normal cocok', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 16, 12)),
        rules: [rule(id: 'rule-1', start: 480, end: 1020)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.matchedRule);
    });

    test('penggunaan tepat pada waktu mulai termasuk', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 16, 8)),
        rules: [rule(id: 'rule-1', start: 480, end: 1020)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.matchedRule);
    });

    test('penggunaan tepat pada waktu selesai tidak termasuk', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 16, 17)),
        rules: [rule(id: 'rule-1', start: 480, end: 1020)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('aturan sepanjang hari cocok pada awal dan akhir hari', () {
      final rules = [rule(id: 'rule-1', start: 0, end: 1440)];
      final categories = [category(id: 'cat-night')];

      final atMidnight = classify(
        record: usage(at: DateTime(2026, 11, 16)),
        rules: rules,
        categories: categories,
      );
      final atLastMinute = classify(
        record: usage(at: DateTime(2026, 11, 16, 23, 59)),
        rules: rules,
        categories: categories,
      );

      expect(atMidnight.outcome, ClassificationOutcome.matchedRule);
      expect(atLastMinute.outcome, ClassificationOutcome.matchedRule);
    });

    test('aturan lintas tengah malam berlaku pada hari yang sama', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 16, 23)),
        rules: [rule(id: 'rule-1', start: 1320, end: 360, mask: mondayBit)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.matchedRule);
    });

    test('aturan dengan endMinute 1440 berlaku sampai akhir hari', () {
      final rules = [rule(id: 'rule-1', start: 1200, end: 1440)];
      final categories = [category(id: 'cat-night')];

      final lateEvening = classify(
        record: usage(at: DateTime(2026, 11, 16, 23, 59)),
        rules: rules,
        categories: categories,
      );
      final lateMorning = classify(
        record: usage(at: DateTime(2026, 11, 16, 11)),
        rules: rules,
        categories: categories,
      );

      expect(lateEvening.outcome, ClassificationOutcome.matchedRule);
      expect(lateMorning.outcome, ClassificationOutcome.unclassified);
    });

    test('hari yang tidak termasuk daysOfWeekMask tidak cocok', () {
      final result = classify(
        record: usage(at: tuesday),
        rules: [rule(id: 'rule-1', start: 480, end: 1020, mask: mondayBit)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('Selasa pukul 02:00 termasuk aturan Senin 22:00 sampai 06:00', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 17, 2)),
        rules: [rule(id: 'rule-1', start: 1320, end: 360, mask: mondayBit)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.matchedRule);
    });

    test('aturan lintas tengah malam tidak berlaku di tengah hari', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 17, 12)),
        rules: [rule(id: 'rule-1', start: 1320, end: 360, mask: mondayBit)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('hari pada aturan lintas tengah malam dihitung dari hari mulai', () {
      // Selasa 23:00 dimiliki aturan hari Selasa, bukan aturan Senin.
      final result = classify(
        record: usage(at: DateTime(2026, 11, 17, 23)),
        rules: [rule(id: 'rule-1', start: 1320, end: 360, mask: mondayBit)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('batas bawah mask Selasa tetap memakai hari Selasa', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 17, 2)),
        rules: [rule(id: 'rule-1', start: 1320, end: 360, mask: tuesdayBit)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('waktu acuan UTC dikonversi ke waktu lokal sebelum dicocokkan', () {
      final localTime = DateTime(2026, 11, 17, 2);
      final rules = [
        rule(id: 'rule-1', start: 1320, end: 360, mask: mondayBit),
      ];
      final categories = [category(id: 'cat-night')];

      final asLocal = classify(
        record: usage(at: localTime),
        rules: rules,
        categories: categories,
      );
      final asUtc = classify(
        record: usage(at: localTime.toUtc()),
        rules: rules,
        categories: categories,
      );

      expect(asLocal.outcome, ClassificationOutcome.matchedRule);
      expect(asUtc.outcome, asLocal.outcome);
    });
  });

  group('Fallback MAIN', () {
    test('tanpa aturan cocok, MAIN valid dipakai', () {
      final result = classify(record: usage(), categories: [mainCategory()]);

      expect(result.outcome, ClassificationOutcome.mainFallback);
      expect(result.category?.id, 'cat-main');
      expect(result.matchedRule, isNull);
    });

    test('MAIN yang dinonaktifkan tidak dipakai', () {
      final result = classify(
        record: usage(),
        categories: [mainCategory(enabled: false)],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
      expect(result.unclassifiedReason, UnclassifiedReason.noValidCategory);
    });

    test('MAIN yang sudah kedaluwarsa tidak dipakai', () {
      final result = classify(
        record: usage(),
        categories: [mainCategory(validUntil: DateTime(2026, 11, 15))],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('MAIN yang belum berlaku tidak dipakai', () {
      final result = classify(
        record: usage(),
        categories: [mainCategory(validFrom: DateTime(2026, 11, 17))],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('MAIN tidak ditemukan menghasilkan UNCLASSIFIED', () {
      final result = classify(
        record: usage(),
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
      expect(result.unclassifiedReason, UnclassifiedReason.noValidCategory);
    });

    test('tanpa kategori valid menghasilkan UNCLASSIFIED', () {
      final result = classify(record: usage());

      expect(result.outcome, ClassificationOutcome.unclassified);
      expect(result.category, isNull);
      expect(result.matchedRule, isNull);
    });

    test('batas tanggal MAIN inklusif pada hari mulai dan hari akhir', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 16, 8)),
        categories: [
          mainCategory(
            validFrom: DateTime(2026, 11, 16),
            validUntil: DateTime(2026, 11, 16),
          ),
        ],
      );

      expect(result.outcome, ClassificationOutcome.mainFallback);
    });

    test('kategori tambahan tidak dipakai sebagai fallback', () {
      final result = classify(
        record: usage(),
        categories: [
          category(
            id: 'cat-night',
            validFrom: DateTime(2026, 11, 1),
            validUntil: DateTime(2026, 11, 30),
          ),
        ],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });
  });

  group('Integritas aturan dan kategori', () {
    test('aturan yang kategorinya disabled menghasilkan UNCLASSIFIED', () {
      final result = classify(
        record: usage(),
        rules: [rule(id: 'rule-1', app: 'com.instagram.android')],
        categories: [
          category(id: 'cat-night', enabled: false),
          mainCategory(),
        ],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
      expect(
        result.unclassifiedReason,
        UnclassifiedReason.matchedRuleInvalidCategory,
      );
      expect(result.matchedRule?.id, 'rule-1');
      expect(result.category, isNull);
    });

    test('aturan yang kategorinya kedaluwarsa menghasilkan UNCLASSIFIED', () {
      final result = classify(
        record: usage(),
        rules: [rule(id: 'rule-1', app: 'com.instagram.android')],
        categories: [
          category(id: 'cat-night', validUntil: DateTime(2026, 11, 15)),
          mainCategory(),
        ],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
      expect(
        result.unclassifiedReason,
        UnclassifiedReason.matchedRuleInvalidCategory,
      );
    });

    test('aturan dari paket lain tidak dipakai untuk paket ini', () {
      final result = classify(
        record: usage(package: otherPackageId),
        rules: [
          rule(
            id: 'rule-1',
            app: 'com.instagram.android',
            categoryId: 'cat-foreign',
          ),
        ],
        categories: [
          category(id: 'cat-foreign', package: packageId),
          mainCategory(id: 'cat-main-2', package: otherPackageId),
        ],
      );

      expect(result.outcome, ClassificationOutcome.mainFallback);
      expect(result.category?.id, 'cat-main-2');
    });

    test('kategori dari paket lain tidak dipakai sebagai MAIN', () {
      final result = classify(
        record: usage(package: otherPackageId),
        categories: [mainCategory(id: 'cat-main-1', package: packageId)],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });

    test('aturan wildcard berlaku untuk catatan tanpa nama aplikasi', () {
      final result = classify(
        record: usage(app: null),
        rules: [rule(id: 'rule-1', app: null)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.matchedRule);
    });

    test('aturan tanpa batas jam tetap menghormati daysOfWeekMask', () {
      final rules = [rule(id: 'rule-1', mask: mondayBit)];
      final categories = [category(id: 'cat-night')];

      final onMonday = classify(
        record: usage(at: monday),
        rules: rules,
        categories: categories,
      );
      final onTuesday = classify(
        record: usage(at: tuesday),
        rules: rules,
        categories: categories,
      );

      expect(onMonday.outcome, ClassificationOutcome.matchedRule);
      expect(onTuesday.outcome, ClassificationOutcome.unclassified);
    });

    test('startMinute sama dengan endMinute adalah interval kosong', () {
      final result = classify(
        record: usage(at: DateTime(2026, 11, 16, 8)),
        rules: [rule(id: 'rule-1', start: 480, end: 480)],
        categories: [category(id: 'cat-night')],
      );

      expect(result.outcome, ClassificationOutcome.unclassified);
    });
  });
}
