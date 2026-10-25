class ParsedCommand {
  final String title;
  final String type;
  final DateTime? dueAt;

  const ParsedCommand({
    required this.title,
    required this.type,
    required this.dueAt,
  });
}

ParsedCommand parseCommand(String input, String fallbackType) {
  final original = input.trim();
  final lower = original.toLowerCase();

  String type = fallbackType;
  if (lower.contains('встреч')) {
    type = 'meeting';
  } else if (lower.contains('напомин')) {
    type = 'reminder';
  } else if (lower.contains('задач')) {
    type = 'task';
  }

  final now = DateTime.now();
  DateTime? date;
  String cleaned = original;

  if (RegExp(r'\bпослезавтра\b', caseSensitive: false).hasMatch(cleaned)) {
    date = DateTime(now.year, now.month, now.day + 2);
    cleaned = cleaned.replaceAll(
      RegExp(r'\bпослезавтра\b', caseSensitive: false),
      '',
    );
  } else if (RegExp(r'\bзавтра\b', caseSensitive: false).hasMatch(cleaned)) {
    date = DateTime(now.year, now.month, now.day + 1);
    cleaned = cleaned.replaceAll(
      RegExp(r'\bзавтра\b', caseSensitive: false),
      '',
    );
  } else if (RegExp(r'\bсегодня\b', caseSensitive: false).hasMatch(cleaned)) {
    date = DateTime(now.year, now.month, now.day);
    cleaned = cleaned.replaceAll(
      RegExp(r'\bсегодня\b', caseSensitive: false),
      '',
    );
  }

  int? hour;
  int? minute;

  final colonTime = RegExp(r'\b(?:в\s*)?([01]?\d|2[0-3])[:.]([0-5]\d)\b')
      .firstMatch(cleaned);

  if (colonTime != null) {
    hour = int.tryParse(colonTime.group(1)!);
    minute = int.tryParse(colonTime.group(2)!);
    cleaned = cleaned.replaceRange(colonTime.start, colonTime.end, ' ');
  } else {
    final hourTime = RegExp(
      r'\bв\s+(\d{1,2})(?:\s*(?:час(?:а|ов)?))?(?:\s*(утра|дня|вечера|ночи))?\b',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (hourTime != null) {
      var parsedHour = int.tryParse(hourTime.group(1)!);
      final period = hourTime.group(2)?.toLowerCase();

      if (parsedHour != null && parsedHour >= 1 && parsedHour <= 12) {
        if (period == 'вечера' && parsedHour < 12) parsedHour += 12;
        if (period == 'дня' && parsedHour < 12) parsedHour += 12;
        if (period == 'ночи' && parsedHour == 12) parsedHour = 0;
        if (period == 'утра' && parsedHour == 12) parsedHour = 0;
        hour = parsedHour;
        minute = 0;
        cleaned = cleaned.replaceRange(hourTime.start, hourTime.end, ' ');
      }
    }
  }

  if (hour != null) {
    date ??= DateTime(now.year, now.month, now.day);
    date = DateTime(date.year, date.month, date.day, hour, minute ?? 0);
  }

  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^\s*(добавь|создай|запиши|поставь|назначь)\s+',
      caseSensitive: false,
    ),
    '',
  );

  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^\s*(мне\s+)?(задачу|напоминание|встречу)\s*',
      caseSensitive: false,
    ),
    '',
  );

  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  cleaned = cleaned.replaceAll(RegExp(r'^[,;:\- ]+|[,;:\- ]+$'), '').trim();

  return ParsedCommand(
    title: cleaned,
    type: type,
    dueAt: date,
  );
}
