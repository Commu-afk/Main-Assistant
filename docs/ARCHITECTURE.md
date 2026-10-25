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
| Уведомления | Платформенные | Windows/Android нативные механизмы |

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
│   ├── chat/    # UI чата + логика диалога
│   ├── llm/     # интеграция llama.cpp, управление моделью
│   ├── stt/     # Whisper
│   ├── tts/     # TTS
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
- Платформенные каналы/плагины для уведомлений
- Векторное хранилище для семантического поиска
- GPU (Vulkan/CUDA) для LLM: текущее железо считает на CPU (~5 ток/с)
