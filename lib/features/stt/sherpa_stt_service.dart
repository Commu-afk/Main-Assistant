import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'sherpa_config.dart';

import '../../core/utils/russian_numbers.dart';

/// Локальное распознавание русской речи через Sherpa-ONNX.
///
/// Схема работы (push-to-talk):
/// 1. [startRecording] — открывает микрофон, копит PCM 16 kHz mono
/// 2. [stopAndTranscribe] — останавливает запись и распознаёт всю фразу
///    оффлайн-моделью (файлы модели лежат локально, системный STT не
///    используется)
class SherpaSttService {
  SherpaSttService._();

  static final SherpaSttService instance = SherpaSttService._();

  static const int sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();

  sherpa_onnx.OfflineRecognizer? _recognizer;
  BytesBuilder? _buffer;
  StreamSubscription<Uint8List>? _audioSub;
  bool _isRecording = false;
  bool _initFailed = false;
  String? _lastError;

  bool get isReady => _recognizer != null;
  bool get isRecording => _isRecording;
  String? get lastError => _lastError;

  /// Загружает модель. Безопасно вызывать повторно.
  Future<void> initialize() async {
    if (_recognizer != null) return;

    sherpa_onnx.initBindings();

    final SherpaModelFiles files;
    try {
      files = await SherpaConfig.load();
    } catch (e) {
      _initFailed = true;
      _lastError = e.toString();
      rethrow;
    }

    final modelType = SherpaConfig.detectModelType(files.dir);

    final modelConfig = sherpa_onnx.OfflineModelConfig(
      transducer: sherpa_onnx.OfflineTransducerModelConfig(
        encoder: files.encoder,
        decoder: files.decoder,
        joiner: files.joiner,
      ),
      tokens: files.tokens,
      modelType: modelType,
      numThreads: 2,
      debug: false,
    );

    _recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(model: modelConfig),
    );

    _initFailed = false;
    _lastError = null;
  }

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Начинает запись с микрофона.
  Future<void> startRecording() async {
    if (_isRecording) return;
    if (_initFailed) {
      // Дадим шанс после того, как пользователь положил модель.
      _initFailed = false;
    }
    if (_recognizer == null) {
      await initialize();
    }

    if (!await _recorder.hasPermission()) {
      throw Exception('Нет доступа к микрофону');
    }

    _buffer = BytesBuilder(copy: false);

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    _audioSub = stream.listen(
      (data) => _buffer?.add(data),
      onError: (Object e) => _lastError = 'Ошибка записи: $e',
    );

    _isRecording = true;
  }

  /// Останавливает запись и возвращает распознанный текст.
  Future<String> stopAndTranscribe() async {
    if (!_isRecording) return '';

    _isRecording = false;

    try {
      await _recorder.stop();
    } catch (_) {}

    await _audioSub?.cancel();
    _audioSub = null;

    final bytes = _buffer?.takeBytes() ?? Uint8List(0);
    _buffer = null;

    if (bytes.isEmpty) return '';

    final samples = _pcm16ToFloat32(bytes);
    if (samples.isEmpty) return '';

    final recognizer = _recognizer;
    if (recognizer == null) {
      throw Exception('Модель распознавания не загружена');
    }

    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      final raw = recognizer.getResult(stream).text.trim();
      // В словаре модели нет цифр, поэтому числа приходят словами
      // («двадцать три»). Приводим их к цифрам для команд и заметок.
      return normalizeRussianNumbers(raw);
    } finally {
      stream.free();
    }
  }

  /// Прерывает запись, ничего не распознавая.
  Future<void> cancel() async {
    if (!_isRecording) return;
    _isRecording = false;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _audioSub?.cancel();
    _audioSub = null;
    _buffer = null;
  }

  Future<void> dispose() async {
    await cancel();
    _recognizer?.free();
    _recognizer = null;
    await _recorder.dispose();
  }

  /// PCM 16-bit little-endian -> Float32 в диапазоне [-1, 1].
  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    final result = Float32List(count);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < count; i++) {
      result[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return result;
  }
}
