// MILIK ARSITEK. firebase_options.dart dibuat oleh `flutterfire configure`.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/app_providers.dart';
import 'core/routes.dart';
import 'core/theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const DatawiseApp());
}

class DatawiseApp extends StatefulWidget {
  const DatawiseApp({super.key});

  @override
  State<DatawiseApp> createState() => _DatawiseAppState();
}

class _DatawiseAppState extends State<DatawiseApp> {
  late final List<SingleChildWidget> _providers = buildAppProviders();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _providers,
      child: MaterialApp(
        title: 'DATAWISE',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        initialRoute: Routes.gate,
        routes: appRoutes,
      ),
    );
  }
}
