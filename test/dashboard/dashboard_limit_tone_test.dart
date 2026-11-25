import 'package:datawise/core/constants.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/services/dashboard_data_limit_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DataLimitSetting setting({int? limit = 100 * kBytesPerMB}) {
    return DataLimitSetting(
      packageId: 'pkg-1',
      dailyLimitBytes: limit,
      isEnabled: true,
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  group('toneForPercent - warna badge Dashboard', () {
    test('79% aman', () {
      expect(toneForPercent(79), DataLimitTone.safe);
    });

    test('80% mulai peringatan', () {
      expect(toneForPercent(80), DataLimitTone.warning);
    });

    test('99% masih peringatan', () {
      expect(toneForPercent(99), DataLimitTone.warning);
    });

    test('100% bahaya (mencapai batas)', () {
      expect(toneForPercent(100), DataLimitTone.danger);
    });

    test('101% bahaya (melebihi batas)', () {
      expect(toneForPercent(101), DataLimitTone.danger);
    });

    test('persentase null tidak diberi status aman', () {
      expect(toneForPercent(null), DataLimitTone.unknown);
      expect(toneForPercent(double.nan), DataLimitTone.unknown);
      expect(toneForPercent(double.infinity), DataLimitTone.unknown);
    });
  });

  group('DashboardDataLimitCalculator - sumber batas', () {
    test('memakai batas manual bila tersedia', () {
      final status = DashboardDataLimitCalculator.evaluate(
        setting(limit: 100 * kBytesPerMB),
        80 * kBytesPerMB,
        plannerDailyTargetBytes: (200 * kBytesPerMB).toDouble(),
      );

      expect(status.isConfigured, isTrue);
      expect(status.source, DataLimitSource.manual);
      expect(status.limitBytes, 100 * kBytesPerMB);
      expect(status.percent, closeTo(80, 0.001));
      expect(status.tone, DataLimitTone.warning);
    });

    test('fallback target Data Planner saat batas manual kosong', () {
      final status = DashboardDataLimitCalculator.evaluate(
        setting(limit: null),
        90 * kBytesPerMB,
        plannerDailyTargetBytes: (100 * kBytesPerMB).toDouble(),
      );

      expect(status.isConfigured, isTrue);
      expect(status.source, DataLimitSource.planner);
      expect(status.limitBytes, 100 * kBytesPerMB);
      expect(status.tone, DataLimitTone.warning);
    });

    test('fallback planner juga dipakai tanpa pengaturan sama sekali', () {
      final status = DashboardDataLimitCalculator.evaluate(
        null,
        20 * kBytesPerMB,
        plannerDailyTargetBytes: (100 * kBytesPerMB).toDouble(),
      );

      expect(status.source, DataLimitSource.planner);
      expect(status.tone, DataLimitTone.safe);
    });

    test('tanpa batas valid tidak dikonfigurasi dan tanpa status', () {
      final status = DashboardDataLimitCalculator.evaluate(null, 50);

      expect(status.isConfigured, isFalse);
      expect(status.source, DataLimitSource.none);
      expect(status.tone, DataLimitTone.unknown);
    });

    test('planner yang tidak valid diabaikan', () {
      final status = DashboardDataLimitCalculator.evaluate(
        null,
        50,
        plannerDailyTargetBytes: 0,
      );

      expect(status.isConfigured, isFalse);
      expect(status.tone, DataLimitTone.unknown);
    });

    test('peringatan yang dinonaktifkan tidak memakai fallback planner', () {
      final status = DashboardDataLimitCalculator.evaluate(
        DataLimitSetting(
          packageId: 'pkg-1',
          dailyLimitBytes: null,
          isEnabled: false,
          updatedAt: DateTime(2026, 1, 1),
        ),
        100 * kBytesPerMB,
        plannerDailyTargetBytes: (100 * kBytesPerMB).toDouble(),
      );

      expect(status.isConfigured, isFalse);
      expect(status.source, DataLimitSource.none);
    });
  });
}
