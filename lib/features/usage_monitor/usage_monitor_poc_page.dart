import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UsageMonitorPocPage extends StatefulWidget {
  const UsageMonitorPocPage({super.key});

  @override
  State<UsageMonitorPocPage> createState() => _UsageMonitorPocPageState();
}

class _UsageMonitorPocPageState extends State<UsageMonitorPocPage> {
  static const MethodChannel channel = MethodChannel('datawise/usage');

  bool? hasPermission;
  bool isLoading = false;
  Map<dynamic, dynamic>? usageResult;
  String message = 'Belum ada pengujian';

  Future<void> checkPermission() async {
    setState(() {
      isLoading = true;
      message = 'Memeriksa izin...';
    });

    try {
      final result = await channel.invokeMethod<bool>('hasUsagePermission');

      setState(() {
        hasPermission = result ?? false;
        message = hasPermission!
            ? 'Izin Usage Access aktif'
            : 'Izin Usage Access belum aktif';
      });
    } on PlatformException catch (e) {
      setState(() {
        message = 'Platform error: ${e.message}';
      });
    } on MissingPluginException {
      setState(() {
        message = 'MethodChannel belum terdaftar';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> openUsageSettings() async {
    try {
      await channel.invokeMethod('openUsageAccessSettings');

      setState(() {
        message = 'Membuka pengaturan Usage Access';
      });
    } catch (e) {
      setState(() {
        message = 'Gagal membuka pengaturan: $e';
      });
    }
  }

  Future<void> readMobileUsage() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);

    setState(() {
      isLoading = true;
      usageResult = null;
      message = 'Membaca penggunaan data...';
    });

    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'getMobileUsage',
        {
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': now.millisecondsSinceEpoch,
        },
      );

      setState(() {
        usageResult = result;
        message = 'Pembacaan selesai';
      });
    } on PlatformException catch (e) {
      setState(() {
        message = 'Platform error: ${e.message}';
      });
    } on MissingPluginException {
      setState(() {
        message = 'MethodChannel belum tersedia';
      });
    } catch (e) {
      setState(() {
        message = 'Terjadi kesalahan: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  String formatBytes(dynamic value) {
    final bytes = (value as num?)?.toDouble() ?? 0;

    if (bytes < 1024) {
      return '${bytes.toStringAsFixed(0)} B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final status = usageResult?['status'];
    final totalBytes = usageResult?['totalBytes'];

    return Scaffold(
      appBar: AppBar(title: const Text('Usage Monitor PoC')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.data_usage, size: 65, color: Colors.deepPurple),
            const SizedBox(height: 12),

            const Text(
              'Pengujian Usage Monitor',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Status Pengujian'),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            ElevatedButton.icon(
              onPressed: isLoading ? null : checkPermission,
              icon: const Icon(Icons.security),
              label: const Text('Periksa Usage Access'),
            ),

            ElevatedButton.icon(
              onPressed: isLoading ? null : openUsageSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Buka Pengaturan Izin'),
            ),

            ElevatedButton.icon(
              onPressed: isLoading ? null : readMobileUsage,
              icon: const Icon(Icons.network_check),
              label: const Text('Baca Penggunaan Data'),
            ),

            const SizedBox(height: 20),

            if (hasPermission != null)
              ListTile(
                leading: Icon(
                  hasPermission! ? Icons.check_circle : Icons.cancel,
                  color: hasPermission! ? Colors.green : Colors.red,
                ),
                title: const Text('Usage Access'),
                subtitle: Text(hasPermission! ? 'Aktif' : 'Belum aktif'),
              ),

            if (usageResult != null) ...[
              const Divider(),
              const Text(
                'Hasil Pembacaan',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              ListTile(title: const Text('Status'), subtitle: Text('$status')),
              ListTile(
                title: const Text('Total Penggunaan'),
                subtitle: Text(formatBytes(totalBytes)),
              ),
              ListTile(
                title: const Text('Total Byte'),
                subtitle: Text('$totalBytes'),
              ),
              ListTile(
                title: const Text('Waktu Mulai'),
                subtitle: Text('${usageResult!['startMillis']}'),
              ),
              ListTile(
                title: const Text('Waktu Akhir'),
                subtitle: Text('${usageResult!['endMillis']}'),
              ),
              ListTile(
                title: const Text('Pesan'),
                subtitle: Text('${usageResult!['message'] ?? '-'}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
