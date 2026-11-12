import 'package:flutter_test/flutter_test.dart';
import 'package:local_assistant/main.dart';

void main() {
  testWidgets('Отображается заголовок приложения', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalAssistantApp());

    expect(find.text('Мой ассистент'), findsOneWidget);
  });
}
