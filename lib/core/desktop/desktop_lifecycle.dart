import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/reminders/reminder_scheduler.dart';
import '../../features/settings/app_settings.dart';

/// Поведение приложения как фоновой программы Windows.
///
/// Держит иконку в трее, скрывает окно вместо закрытия и умеет прописывать
/// автозапуск с ключом `--hidden`. Планировщик напоминаний при этом продолжает
/// работать, даже когда окна не видно.
class DesktopLifecycle extends ChangeNotifier with WindowListener {
  DesktopLifecycle._();

  static final DesktopLifecycle instance = DesktopLifecycle._();

  static const String _autostartName = 'Мой ассистент';
  static const String _trayIconAsset = 'assets/images/tray_icon.ico';

  TrayIcon? _trayIcon;
  Menu? _menu;
  MenuItem? _autostartItem;

  bool _initialized = false;
  bool _trayReady = false;
  bool _quitting = false;

  bool _autostartConfigured = false;
  bool _autostartEnabled = false;
  String? _autostartError;

  /// Трей и автозапуск реализованы только для Windows.
  bool get isSupported => !kIsWeb && Platform.isWindows;

  bool get isInitialized => _initialized;

  bool get trayReady => _trayReady;

  bool get closeToTray => AppSettings.instance.closeToTray;

  bool get autostartSupported => isSupported && _autostartConfigured;

  bool get autostartEnabled => _autostartEnabled;

  String? get autostartError => _autostartError;

  /// Инициализация окна, трея и автозапуска.
  ///
  /// Если приложение запущено скрыто, но трей создать не удалось, окно
  /// показываем принудительно — иначе им нельзя будет управлять.
  Future<bool> initialize({bool startHidden = false}) async {
    if (!isSupported) return false;
    if (_initialized) return _trayReady;

    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
    } catch (e) {
      debugPrint('Управление окном недоступно: $e');
    }

    _setupAutostart();
    await _refreshAutostartState();

    try {
      _trayReady = await _createTray();
    } catch (e) {
      _trayReady = false;
      debugPrint('Не удалось создать иконку в трее: $e');
    }

    _initialized = true;

    if (startHidden && !_trayReady) {
      await showWindow();
    }

    return _trayReady;
  }

  Future<void> showWindow() async {
    if (!isSupported) return;
    try {
      await windowManager.show();
      // ShowWindowAsync из window_manager применяется в цикле сообщений окна,
      // поэтому фокус запрашиваем с небольшой паузой.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await windowManager.focus();
    } catch (e) {
      debugPrint('Не удалось показать окно: $e');
    }
  }

  Future<void> hideToTray() async {
    if (!isSupported) return;
    try {
      await windowManager.hide();
    } catch (e) {
      debugPrint('Не удалось скрыть окно: $e');
    }
  }

  Future<void> setCloseToTray(bool value) async {
    await AppSettings.instance.setCloseToTray(value);
    notifyListeners();
  }

  Future<bool> setAutostart(bool value) async {
    if (!autostartSupported) return false;

    try {
      final ok = value
          ? await LaunchAtStartup.instance.enable()
          : await LaunchAtStartup.instance.disable();

      if (ok) {
        _autostartEnabled = value;
        _autostartError = null;
      } else {
        _autostartError = 'Windows не разрешила изменить автозапуск';
      }
      notifyListeners();
      return ok;
    } catch (e) {
      _autostartError = '$e';
      debugPrint('Не удалось изменить автозапуск: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;

    ReminderScheduler.instance.stop();

    _trayIcon?.dispose();
    _trayIcon = null;
    _menu?.dispose();
    _menu = null;

    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (e) {
      debugPrint('Не удалось закрыть приложение штатно: $e');
      exit(0);
    }
  }

  void _setupAutostart() {
    try {
      LaunchAtStartup.instance.setup(
        appName: _autostartName,
        // Кавычки обязательны: путь может содержать пробелы.
        appPath: '"${Platform.resolvedExecutable}"',
        args: const ['--hidden'],
      );
      _autostartConfigured = true;
    } catch (e) {
      _autostartConfigured = false;
      _autostartError = '$e';
      debugPrint('Автозапуск недоступен: $e');
    }
  }

  Future<void> _refreshAutostartState() async {
    if (!_autostartConfigured) return;

    try {
      _autostartEnabled = await LaunchAtStartup.instance.isEnabled();
      _autostartError = null;
    } catch (e) {
      _autostartError = '$e';
      debugPrint('Не удалось прочитать состояние автозапуска: $e');
    }
  }

  Future<bool> _createTray() async {
    final icon = TrayIcon.create();
    if (icon == null) return false;

    final menu = Menu.create();
    if (menu == null) {
      icon.dispose();
      return false;
    }

    final image = ImageAsset.fromAsset(_trayIconAsset);
    if (image == null) {
      debugPrint('Не найден файл иконки трея: $_trayIconAsset');
      icon.dispose();
      menu.dispose();
      return false;
    }

    icon.icon = image;
    icon.setTooltip('Мой ассистент · напоминания работают');
    icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);

    final openItem = MenuItem.createWithLabelAndType(
      'Открыть',
      MenuItemType.normal,
    );
    openItem?.addListener((event) async {
      if (event is MenuItemClickedEvent) await showWindow();
    });
    if (openItem != null) menu.addItem(openItem);

    final checkItem = MenuItem.createWithLabelAndType(
      'Проверить напоминания',
      MenuItemType.normal,
    );
    checkItem?.addListener((event) async {
      if (event is! MenuItemClickedEvent) return;
      final fired = await ReminderScheduler.instance.checkNow();
      icon.setTooltip(
        fired > 0
            ? 'Мой ассистент · показано напоминаний: $fired'
            : 'Мой ассистент · просроченных напоминаний нет',
      );
    });
    if (checkItem != null) menu.addItem(checkItem);

    menu.addSeparator();

    final autostartItem = MenuItem.createWithLabelAndType(
      'Запускать при входе в Windows',
      MenuItemType.checkbox,
    );
    if (autostartItem != null) {
      autostartItem.state = _autostartEnabled
          ? MenuItemState.checked
          : MenuItemState.unchecked;
      autostartItem.addListener((event) async {
        if (event is! MenuItemClickedEvent) return;
        final next = _autostartItem?.state != MenuItemState.checked;
        if (await setAutostart(next)) {
          _autostartItem?.state = next
              ? MenuItemState.checked
              : MenuItemState.unchecked;
        }
      });
      menu.addItem(autostartItem);
      _autostartItem = autostartItem;
    }

    menu.addSeparator();

    final quitItem = MenuItem.createWithLabelAndType(
      'Выход',
      MenuItemType.normal,
    );
    quitItem?.addListener((event) async {
      if (event is MenuItemClickedEvent) await quit();
    });
    if (quitItem != null) menu.addItem(quitItem);

    icon.addListener((event) async {
      if (event is TrayIconClickedEvent ||
          event is TrayIconDoubleClickedEvent) {
        await showWindow();
      }
    });

    icon.setContextMenu(menu);
    icon.setVisible(true);

    _trayIcon = icon;
    _menu = menu;
    return true;
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    if (closeToTray) {
      hideToTray();
    } else {
      quit();
    }
  }
}
