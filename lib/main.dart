import 'dart:async';
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

  final startup = Stopwatch()..start();
  final startHidden = args.contains('--hidden');

  // Настройки и трей не нужны для первого кадра: запускаем их в фоне.
  // Окно показывается по первому кадру (SetNextFrameCallback в runner).
  final settingsReady = AppSettings.instance.load();
  final desktopReady = DesktopLifecycle.instance.initialize(
    startHidden: startHidden,
  );

  runApp(const LocalAssistantApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    debugPrint('[startup] первый кадр: ${startup.elapsedMilliseconds} мс');

    try {
      await Future.wait([settingsReady, desktopReady]);
    } catch (e) {
      debugPrint('Фоновая инициализация не удалась: $e');
    }

    debugPrint('[startup] трей и настройки: ${startup.elapsedMilliseconds} мс');
  });
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
