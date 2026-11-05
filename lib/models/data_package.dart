// MILIK ARSITEK. KONTRAK BEKU #3.
import 'date_codec.dart';

const Object _unset = Object();

class DataPackage {
  final int? id;
  final String userId, name, operator;
  final int totalBytes, initialUsedBytes;
  final DateTime startDate, endDate; // jam 00:00 lokal
  final int? price;
  final bool isActive;
  final DateTime createdAt, updatedAt;

  const DataPackage({
    this.id,
    required this.userId,
    required this.name,
    required this.operator,
    required this.totalBytes,
    required this.initialUsedBytes,
    required this.startDate,
    required this.endDate,
    required this.price,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Hanya dipanggil oleh repository.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        'operator': operator,
        'total_bytes': totalBytes,
        'initial_used_bytes': initialUsedBytes,
        'start_date': dateToDb(startDate),
        'end_date': dateToDb(endDate),
        'price': price,
        'is_active': isActive ? 1 : 0,
        'created_at': timeToMs(createdAt),
        'updated_at': timeToMs(updatedAt),
      };

  /// Hanya dipanggil oleh repository.
  factory DataPackage.fromMap(Map<String, Object?> m) => DataPackage(
        id: m['id'] as int?,
        userId: m['user_id'] as String,
        name: m['name'] as String,
        operator: m['operator'] as String,
        totalBytes: m['total_bytes'] as int,
        initialUsedBytes: m['initial_used_bytes'] as int,
        startDate: dateFromDb(m['start_date'] as String),
        endDate: dateFromDb(m['end_date'] as String),
        price: m['price'] as int?,
        isActive: (m['is_active'] as int) == 1,
        createdAt: timeFromMs(m['created_at'] as int),
        updatedAt: timeFromMs(m['updated_at'] as int),
      );

  /// `id` dan `price` boleh di-set ke null dengan mengirim `null` eksplisit.
  DataPackage copyWith({
    Object? id = _unset,
    String? userId,
    String? name,
    String? operator,
    int? totalBytes,
    int? initialUsedBytes,
    DateTime? startDate,
    DateTime? endDate,
    Object? price = _unset,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      DataPackage(
        id: identical(id, _unset) ? this.id : id as int?,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        operator: operator ?? this.operator,
        totalBytes: totalBytes ?? this.totalBytes,
        initialUsedBytes: initialUsedBytes ?? this.initialUsedBytes,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        price: identical(price, _unset) ? this.price : price as int?,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
