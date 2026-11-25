// Usage Classification Service: menjembatani Classification Engine dengan
// repository. Semua penyimpanan memakai transaksi yang sudah tersedia di
// UsageRepository.
import '../../models/models.dart';
import '../../repositories/classification_rule_repository.dart';
import '../../repositories/quota_category_repository.dart';
import '../../repositories/usage_repository.dart';
import 'classification_engine.dart';

class StoredUsageClassification {
  const StoredUsageClassification({
    required this.usageRecordId,
    required this.classification,
    required this.allocation,
  });

  final String usageRecordId;
  final ClassificationResult classification;
  final UsageAllocation allocation;
}

class UsageClassificationService {
  UsageClassificationService({
    required this.ruleRepository,
    required this.categoryRepository,
    required this.usageRepository,
    this.engine = const ClassificationEngine(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ClassificationRuleRepository ruleRepository;
  final QuotaCategoryRepository categoryRepository;
  final UsageRepository usageRepository;
  final ClassificationEngine engine;
  final DateTime Function() _clock;

  /// Mengklasifikasikan [record] lalu menyimpan record beserta alokasinya
  /// dalam satu transaksi. Bila penyimpanan alokasi gagal, record ikut batal.
  Future<StoredUsageClassification> classifyAndStore(UsageRecord record) async {
    // Trigger database hanya mengizinkan alokasi untuk APP_USAGE non-Wi-Fi.
    // Tolak lebih awal dengan pesan yang jelas daripada gagal di repository.
    if (record.recordScope != UsageRecordScope.appUsage ||
        record.source != UsageSource.android ||
        record.networkType == NetworkType.wifi) {
      throw const AppException(
        AppException.validation,
        'Klasifikasi otomatis hanya berlaku untuk pemakaian aplikasi Android.',
      );
    }

    final rules = await ruleRepository.getByPackage(record.packageId);
    final categories = await categoryRepository.getByPackage(record.packageId);

    final classification = engine.classify(
      record: record,
      rules: rules,
      categories: categories,
    );

    final createdAt = _clock();

    UsageAllocation buildAllocation(String usageRecordId) {
      final method = switch (classification.outcome) {
        ClassificationOutcome.matchedRule => AllocationMethod.autoRule,
        ClassificationOutcome.mainFallback => AllocationMethod.mainFallback,
        ClassificationOutcome.unclassified => AllocationMethod.unclassified,
      };

      return UsageAllocation(
        packageId: record.packageId,
        usageRecordId: usageRecordId,
        quotaCategoryId: classification.category?.id,
        // UNCLASSIFIED tidak boleh menyimpan referensi aturan.
        classificationRuleId:
            classification.outcome == ClassificationOutcome.matchedRule
            ? classification.matchedRule?.id
            : null,
        allocatedBytes: record.totalBytes,
        allocationMethod: method,
        createdAt: createdAt,
      );
    }

    late UsageAllocation allocation;

    // upsertRecordWithAllocations menangani penyimpanan record dan alokasi
    // dalam satu transaksi serta membuang alokasi lama saat record di-upsert.
    final usageRecordId = await usageRepository.upsertRecordWithAllocations(
      record,
      (id) {
        allocation = buildAllocation(id);
        return [allocation];
      },
    );

    return StoredUsageClassification(
      usageRecordId: usageRecordId,
      classification: classification,
      allocation: allocation,
    );
  }
}
