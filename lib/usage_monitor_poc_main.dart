import 'package:flutter/material.dart';

import 'features/usage_monitor/usage_monitor_poc_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: UsageMonitorPocPage(),
    ),
  );
}
