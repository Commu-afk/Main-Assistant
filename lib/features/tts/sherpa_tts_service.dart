import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'tts_model.dart';

/// Локальная озвучка русского текста через Sherpa-ONNX (модель Piper/VITS).
class SherpaTtsService {
  SherpaTtsService._();

  static final SherpaTtsService instance = SherpaTtsService._();

  final AudioPlayer _player = AudioPlayer();

  sherpa_onnx.OfflineTts? _tts;
  bool _initializing = false;
  String? _lastError;
  bool _speaking = false;
  Completer<void>? _playbackDone;

  bool get isReady => _tts != null;
  bool get isSpeaking => _speaking;
  String? get lastError => _lastError;

  Future<void> initialize() async {
    if (_tts != null || _initializing) return;
    _initializing = true;

    try {
      sherpa_onnx.initBindings();

      final files = await TtsModel.ensure();

      final config = sherpa_onnx.OfflineTtsConfig(
        model: sherpa_onnx.OfflineTtsModelConfig(
          vits: sherpa_onnx.OfflineTtsVitsModelConfig(
            model: files.model,
            tokens: files.tokens,
            dataDir: files.dataDir,
          ),
          numThreads: 2,
          debug: false,
        ),
      );

      _tts = sherpa_onnx.OfflineTts(config);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  /// Озвучивает текст. Возвращает false, если синтез не удался.
  Future<bool> speak(String text, {double speed = 1.0}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    await initialize();
    final tts = _tts;
    if (tts == null) {
      throw Exception(_lastError ?? 'Модель озвучки не загружена');
    }

    final audio = tts.generate(text: trimmed, sid: 0, speed: speed);
    if (audio.samples.isEmpty) return false;

    final dir = await getApplicationSupportDirectory();
    final wav = File(p.join(dir.path, 'tts_last.wav'));

    sherpa_onnx.writeWave(
      filename: wav.path,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );

    _speaking = true;
    try {
      await _player.stop();
      final done = Completer<void>();
      _playbackDone = done;

      final sub = _player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });

      await _player.play(DeviceFileSource(wav.path));
      await done.future;
      await sub.cancel();
    } finally {
      _playbackDone = null;
      _speaking = false;
    }
    return true;
  }

  Future<void> stop() async {
    final done = _playbackDone;
    if (done != null && !done.isCompleted) done.complete();
    await _player.stop();
    _speaking = false;
  }

  Future<void> dispose() async {
    _tts?.free();
    _tts = null;
    await _player.dispose();
  }
}
