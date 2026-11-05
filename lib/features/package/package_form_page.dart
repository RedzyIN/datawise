// PEMILIK: Anggota B. Route '/package/form'. Argumen: DataPackage? (null = tambah baru).
import 'package:flutter/material.dart';

import '../../models/models.dart';

class PackageFormPage extends StatelessWidget {
  const PackageFormPage({super.key});

  @override
  Widget build(BuildContext context) {
    final editing = ModalRoute.of(context)?.settings.arguments as DataPackage?;
    return Scaffold(
      appBar: AppBar(title: Text(editing == null ? 'Tambah Paket' : 'Ubah Paket')),
      body: const Center(child: Text('TODO(B): Form Paket')),
    );
  }
}
