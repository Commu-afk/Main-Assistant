# ARCHITECTURE

## Стек (фактически реализовано)
| Компонент | Технология | Примечание |
|---|---|---|
| UI | Flutter | Единый код для Windows/Android |
| LLM | Qwen2.5-1.5B-Instruct GGUF (Q4_K_M) | Квантованная, оффлайн, ~1 ГБ |
| Инференс LLM | llama.cpp через пакет `llamadart` | Нативные DLL подтягиваются build-hook'ом |
| STT | sherpa-onnx + zipformer-ru | Вместо Whisper: 68 МБ, быстро, оффлайн |
| TTS | sherpa-onnx + Piper ru_RU-irina | VITS, локально, русский голос |
| БД | SQLite | sqflite/sqflite_common_ffi |
| Поиск | FTS5 -> семантический | Постепенный переход |
| Уведомления | `flutter_local_notifications` (WinRT-тосты) | Android — позже |

### Почему не Whisper и не «чистый» FFI
- Whisper в sherpa-onnx даёт пунктуацию, но весит 0.5–1.5 ГБ и медленнее.
  Для команд и коротких фраз хватает zipformer-ru (int8, ~600 мс на фразу).
- Свой FFI к llama.cpp — много ручной работы (CMake, сборка под 2 платформы).
  `llamadart` уже собирает и поставляет нативные библиотеки.


## Структура модулей
```
lib/
├── core/        # app config, constants, utils, di, theme
├── data/        # db, models, repositories
├── features/
│   ├── assistant/ # экран задач и записей
│   ├── chat/    # UI чата + логика диалога
│   ├── llm/     # интеграция llama.cpp, управление моделью
│   ├── reminders/# планировщик и системные уведомления
│   ├── stt/     # sherpa-onnx (zipformer-ru)
│   ├── tts/     # sherpa-onnx (Piper ru_RU-irina)
│   ├── tasks/   # заметки/задачи/напоминания
│   └── settings/# настройки
└── shared/      # widgets, extensions, helpers
```

## Потоки данных (базовые)
1. Пользователь вводит текст/голос -> `stt` (при голосе) -> текст
2. Текст отправляется в `llm` через `llama.cpp` -> ответ
3. Ответ можно озвучить через `tts`
4. Сообщения сохраняются в `data/db` (SQLite)
5. Поиск работает по БД (FTS5)

## Голосовой цикл
В чате включён по умолчанию: 🎤 -> запись -> «стоп» -> распознавание ->
вопрос сразу уходит модели -> ответ озвучивается автоматически.
Флаги `autoSpeak` и `voiceLoop` лежат в `app_settings.json` в support-dir
и переключаются в меню чата. Новая запись или новый вопрос останавливают
текущую озвучку; ручная остановка генерации отменяет автоозвучку.

## Напоминания
- БД: таблица `tasks` (версия 3), у записи есть `due_at` и `notified_at`.
- `ReminderScheduler` (singleton, слушатели — `ChangeNotifier`) проверяет
  `due_at <= now`, `is_done = 0`, `notified_at IS NULL` при старте приложения
  и раз в 20 секунд; показывает тост и пишет `notified_at`, чтобы не повторять.
- `NotificationService` инкапсулирует `flutter_local_notifications`:
  `WindowsInitializationSettings` с постоянным AUMID/GUID, тост с длинным
  показом. На других платформах — заглушка (Android отдельным этапом).
- Планировщик живёт внутри приложения: при закрытом приложении уведомлений
  нет. Варианты дальше — автозапуск или задача в Планировщике Windows.

## Модели
Хранить вне git. Фактическое расположение:
- STT: `assets/stt/sherpa/ru/` (объявляется в pubspec, копируется в support-dir)
- TTS: `assets/tts/sherpa/ru.zip` (zip распаковывается в support-dir)
- LLM: `assets/models/*.gguf` — в assets НЕ объявляется, ищется на диске:
  1. `LOCAL_ASSISTANT_MODEL`
  2. путь, сохранённый вручную (`llm_settings.json` в support-dir)
  3. `<папка exe>/models/`
  4. `<рабочая папка>/assets/models/` (удобно при `flutter run`)
  5. `<support-dir>/models/`

## Нативные библиотеки LLM и старые CPU
`llamadart` скачивает предсобранный llama.cpp (тег `v0.7.0-2` в
`leehack/llamadart-native`, коммит llama.cpp `620d222`) build-hook'ом:
`dart run`/`flutter build` кладут DLL в `.dart_tool/lib`, кэш
`.dart_tool/hooks_runner/...` и рядом с exe.

Их `ggml-cpu.dll` собран с AVX2 (`GGML_NATIVE=OFF` -> включены AVX2/BMI2).
На CPU без AVX2 плагин отказывается загружаться, и llama.cpp не стартует
даже с Vulkan-бэкендом (CPU-бэкенд обязателен).

Решение на такой машине: собрать `ggml-cpu.dll` из **того же коммита** llama.cpp
с `-DGGML_AVX2=OFF -DGGML_BMI2=OFF -DGGML_AVX=ON -DGGML_SSE42=ON`
(`tool/build_ggml_cpu.ps1`) и подменить файл везде, откуда его берут hook и
сборка (`tool/patch_ggml_cpu.ps1`). Коммит обязательно должен совпадать —
плагин и `ggml-base.dll` связаны ABI.

Для других машин ничего делать не нужно: обычная предсобранная DLL работает.

## Решения на будущее
- Выбор модели и параметров генерации в экране настроек
- Android: канал уведомлений, иконка, разрешение POST_NOTIFICATIONS
- Уведомления при закрытом приложении (автозапуск / Планировщик Windows)
- Векторное хранилище для семантического поиска
- GPU (Vulkan/CUDA) для LLM: текущее железо считает на CPU (~5 ток/с)
