/// Предустановленные теги задач.
///
/// Список фиксированный: пользователь не создаёт теги, а выбирает один из
/// готовых. `null` в базе означает «без тега».
class TaskTags {
  TaskTags._();

  static const String work = 'Работа';
  static const String home = 'Дом';
  static const String routines = 'Рутины';

  static const List<String> all = [work, home, routines];
}
