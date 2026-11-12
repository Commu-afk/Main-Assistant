import 'package:flutter/material.dart';

import '../../core/desktop/desktop_lifecycle.dart';
import 'app_settings.dart';

/// Настройки фоновой работы в Windows: автозапуск и закрытие в трей.
class DesktopSettingsDialog extends StatefulWidget {
  const DesktopSettingsDialog({super.key});

  @override
  State<DesktopSettingsDialog> createState() => _DesktopSettingsDialogState();
}

class _DesktopSettingsDialogState extends State<DesktopSettingsDialog> {
  final _lifecycle = DesktopLifecycle.instance;

  late bool _autostart = _lifecycle.autostartEnabled;
  late bool _closeToTray = AppSettings.instance.closeToTray;

  bool _autostartBusy = false;
  String? _error;

  Future<void> _toggleAutostart(bool value) async {
    setState(() {
      _autostartBusy = true;
      _error = null;
    });

    final ok = await _lifecycle.setAutostart(value);
    if (!mounted) return;

    setState(() {
      _autostartBusy = false;
      _autostart = _lifecycle.autostartEnabled;
      _error = ok ? null : (_lifecycle.autostartError ?? 'Не удалось');
    });
  }

  Future<void> _toggleCloseToTray(bool value) async {
    setState(() => _closeToTray = value);
    await _lifecycle.setCloseToTray(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.desktop_windows_outlined),
          SizedBox(width: 10),
          Text('Работа в Windows'),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autostart,
                onChanged: _autostartBusy || !_lifecycle.autostartSupported
                    ? null
                    : _toggleAutostart,
                title: const Text('Запускать при входе в Windows'),
                subtitle: Text(
                  _lifecycle.autostartSupported
                      ? 'Приложение откроется скрыто в трее, напоминания '
                            'продолжат работать'
                      : 'Автозапуск недоступен на этой системе',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _closeToTray,
                onChanged: _toggleCloseToTray,
                title: const Text('Закрывать окно в трей'),
                subtitle: const Text(
                  'Крестик скрывает окно, приложение остаётся в трее и '
                  'продолжает проверять напоминания',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Напоминания проверяются каждые 20 секунд, пока приложение '
                'работает — в том числе когда окно скрыто в трей. '
                'Полностью закрыть приложение можно через меню иконки в трее.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
