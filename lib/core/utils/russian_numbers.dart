/// Преобразование русских числительных в цифры.
///
/// Акустическая модель распознаёт числа словами («двадцать три»), потому что
/// в её словаре нет цифровых токенов. Для разбора команд нужны цифры.
library;

const Map<String, int> _numberWords = {
  'ноль': 0,
  'нуль': 0,
  'один': 1,
  'одна': 1,
  'одно': 1,
  'два': 2,
  'две': 2,
  'три': 3,
  'четыре': 4,
  'пять': 5,
  'шесть': 6,
  'семь': 7,
  'восемь': 8,
  'девять': 9,
  'десять': 10,
  'одиннадцать': 11,
  'двенадцать': 12,
  'тринадцать': 13,
  'четырнадцать': 14,
  'пятнадцать': 15,
  'шестнадцать': 16,
  'семнадцать': 17,
  'восемнадцать': 18,
  'девятнадцать': 19,
  'двадцать': 20,
  'тридцать': 30,
  'сорок': 40,
  'пятьдесят': 50,
  'шестьдесят': 60,
  'семьдесят': 70,
  'восемьдесят': 80,
  'девяносто': 90,
  'сто': 100,
  'двести': 200,
  'триста': 300,
  'четыреста': 400,
  'пятьсот': 500,
  'шестьсот': 600,
  'семьсот': 700,
  'восемьсот': 800,
  'девятьсот': 900,
  'тысяча': 1000,
  'тысячи': 1000,
  'тысяч': 1000,
};

final RegExp _wordPattern = RegExp(r'[А-Яа-яЁё]+');

/// Заменяет подряд идущие числительные на число: «через двадцать три минуты»
/// -> «через 23 минуты».
///
/// Пунктуация и регистр остального текста сохраняются.
String normalizeRussianNumbers(String input) {
  final words = _wordPattern.allMatches(input).toList();
  if (words.isEmpty) return input;

  final buffer = StringBuffer();
  var cursor = 0;
  var i = 0;

  while (i < words.length) {
    final value = _numberWords[words[i].group(0)!.toLowerCase()];
    if (value == null) {
      i++;
      continue;
    }

    var total = 0;
    var current = 0;
    var lastIndex = i;
    var j = i;

    while (j < words.length) {
      final word = words[j].group(0)!.toLowerCase();
      final wordValue = _numberWords[word];
      if (wordValue == null) break;

      // Числительные считаем одним числом, только если между ними одни пробелы.
      if (j > i) {
        final gap = input.substring(words[j - 1].end, words[j].start);
        if (gap.trim().isNotEmpty) break;
      }

      if (wordValue >= 1000) {
        total += (current == 0 ? 1 : current) * wordValue;
        current = 0;
      } else {
        current += wordValue;
      }

      lastIndex = j;
      j++;
    }

    buffer.write(input.substring(cursor, words[i].start));
    buffer.write(total + current);
    cursor = words[lastIndex].end;
    i = lastIndex + 1;
  }

  buffer.write(input.substring(cursor));
  return buffer.toString();
}
