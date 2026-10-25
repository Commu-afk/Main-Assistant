import 'package:flutter/material.dart';

import '../features/assistant/assistant_screen.dart';
import '../features/chat/chat_screen.dart';

/// Нижняя навигация: записи и чат с локальной моделью.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// Чат создаём при первом открытии вкладки: модель на 1 ГБ не должна
  /// грузиться при запуске, если пользователь работает только с задачами.
  /// Дальше IndexedStack держит экран живым.
  bool _chatOpened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const AssistantScreen(),
          _chatOpened ? const ChatScreen() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() {
          _index = value;
          if (value == 1) _chatOpened = true;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Задачи',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Чат',
          ),
        ],
      ),
    );
  }
}
