// PEMILIK: Anggota B. KONTRAK BEKU (dokumen B bagian 11.3).
// TODO(B): validasi dulu (PackageValidator), tangkap AppException, reload setelah sukses.
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/package_repository.dart';

class PackageProvider extends ChangeNotifier {
  PackageProvider(PackageRepository repository) : _repository = repository;

  // ignore: unused_field
  final PackageRepository _repository;

  List<DataPackage> get packages => const []; // terbaru dulu
  DataPackage? get activePackage => null;
  bool get isLoading => false;
  String? get errorMessage => null; // null = tidak ada error

  Future<void> load(String userId) async => throw UnimplementedError('TODO(B)');
  Future<bool> addPackage(DataPackage p) async => throw UnimplementedError('TODO(B)');
  Future<bool> updatePackage(DataPackage p) async => throw UnimplementedError('TODO(B)');
  Future<bool> deletePackage(int id, String userId) async =>
      throw UnimplementedError('TODO(B)');
  Future<void> setActive(String userId, int packageId) async =>
      throw UnimplementedError('TODO(B)');
  void clearError() {}
}
