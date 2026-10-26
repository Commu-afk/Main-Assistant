import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app_shell.dart';
import 'core/desktop/desktop_lifecycle.dart';
import 'features/settings/app_settings.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
  }

  await AppSettings.instance.load();

  final startHidden = args.contains('--hidden');
  await DesktopLifecycle.instance.initialize(startHidden: startHidden);

  runApp(const LocalAssistantApp());
}

class LocalAssistantApp extends StatelessWidget {
  const LocalAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мой ассистент',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
