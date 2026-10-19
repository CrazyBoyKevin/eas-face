import 'dart:math' as math;
import 'package:eas_face/eas_face.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'liveness_preprocessing.dart';

/// One frame's anti-spoof score. A high value alone does not confirm liveness.
class LivenessFrameResult {
  const LivenessFrameResult({
    required this.liveScore,
    required this.face,
    required this.preprocessTime,
    required this.inferenceTime,
    required this.elapsed,
    this.modelScores = const {},
  });
  final double liveScore;
  final Map<String, double> modelScores;
  final FaceDetection face;
  final Duration preprocessTime, inferenceTime, elapsed;
  Map<String, Object> toJson() => {
    'liveScore': _round(liveScore),
    'modelScores': modelScores.map(
      (key, value) => MapEntry(key, _round(value)),
    ),
    'preprocessMs': _ms(preprocessTime),
    'inferenceMs': _ms(inferenceTime),
    'elapsedMs': _ms(elapsed),
    'faceBox': {
      'x': face.x.round(),
      'y': face.y.round(),
      'width': face.width.round(),
      'height': face.height.round(),
    },
  };
  static double _round(double v) => double.parse(v.toStringAsFixed(2));
  static double _ms(Duration d) => _round(d.inMicroseconds / 1000);
}

/// MiniFASNetV2 (2.7x) and MiniFASNetV1SE (4x), both 80x80.
/// Conservative agreement: liveScore is the lower of the two live scores.
/// This differs from upstream averaging and needs device-specific evaluation.
/// Call serially with upright, unmirrored ORIGINAL camera pixels and a box in
/// those same pixels, not aligned/color-corrected recognition previews.
class FaceLivenessEngine {
  static const modelAsset =
      'packages/eas_face_liveness/assets/models/minifasnet_v2.onnx';
  static const contextModelAsset =
      'packages/eas_face_liveness/assets/models/minifasnet_v1se.onnx';
  static bool _licenseRegistered = false;
  OrtSession? _session, _contextSession;
  Future<void>? _loading;
  bool _busy = false, _closed = false;
  bool get isReady => !_closed && _session != null && _contextSession != null;

  Future<void> initialize() {
    if (_closed) throw StateError('活体引擎已关闭');
    return _loading ??= _load();
  }

  @protected
  Future<OrtSession> createModelSession() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError('eas_face_liveness 仅支持 Android 和 iOS');
    }
    return OnnxRuntime().createSessionFromAsset(
      modelAsset,
      options: OrtSessionOptions(intraOpNumThreads: 2, interOpNumThreads: 1),
    );
  }

  @protected
  Future<OrtSession> createContextModelSession() =>
      OnnxRuntime().createSessionFromAsset(
        contextModelAsset,
        options: OrtSessionOptions(intraOpNumThreads: 2, interOpNumThreads: 1),
      );

  Future<void> _load() async {
    try {
      if (!_licenseRegistered) {
        _licenseRegistered = true;
        LicenseRegistry.addLicense(() async* {
          yield LicenseEntryWithLineBreaks(
            ['MiniFASNet / Minivision'],
            await rootBundle.loadString(
              'packages/eas_face_liveness/licenses/minifasnet.LICENSE',
            ),
          );
        });
      }
      _session ??= await createModelSession();
      _contextSession ??= await createContextModelSession();
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<LivenessFrameResult> evaluateFrame(
    img.Image frame,
    FaceDetection face,
  ) async {
    if (_closed) throw StateError('活体引擎已关闭');
    if (_busy) throw StateError('活体检测正在进行中，请丢弃积压帧');
    _busy = true;
    final watch = Stopwatch()..start();
    try {
      await initialize();
      var preprocessTime = Duration.zero;
      var inferenceTime = Duration.zero;
      final scores = <String, double>{};
      for (final context in [false, true]) {
        final prep = Stopwatch()..start();
        final data = await compute(
          context ? prepareLivenessContextInput : prepareLivenessInput,
          (frame, face),
        );
        preprocessTime += prep.elapsed;
        final inference = Stopwatch()..start();
        final score = await _infer(
          context ? _contextSession! : _session!,
          data,
        );
        inferenceTime += inference.elapsed;
        scores[context ? 'context4' : 'texture2_7'] = score;
      }
      return LivenessFrameResult(
        liveScore: scores.values.reduce(math.min),
        modelScores: Map.unmodifiable(scores),
        face: face,
        preprocessTime: preprocessTime,
        inferenceTime: inferenceTime,
        elapsed: watch.elapsed,
      );
    } finally {
      _busy = false;
    }
  }

  Future<double> _infer(OrtSession session, List<double> data) async {
    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      input = await OrtValue.fromList(data, [1, 3, 80, 80]);
      outputs = await session.run({session.inputNames.single: input});
      final ids = [input.id, ...outputs.values.map((v) => v.id)];
      if (ids.toSet().length != ids.length || outputs.length != 1) {
        throw StateError('活体模型返回无效张量');
      }
      final raw = await outputs.values.single.asFlattenedList();
      final logits = raw.map((v) => (v as num).toDouble()).toList();
      if (logits.length != 3 || logits.any((v) => !v.isFinite)) {
        throw StateError('活体模型返回无效分数');
      }
      final peak = logits.reduce(math.max);
      final exps = logits.map((v) => math.exp(v - peak)).toList();
      return exps[1] / exps.reduce((a, b) => a + b);
    } finally {
      final tensors = <String, OrtValue>{
        if (input != null) input.id: input,
        for (final v in outputs?.values ?? <OrtValue>[]) v.id: v,
      };
      for (final v in tensors.values) {
        await v.dispose();
      }
    }
  }

  Future<void> close() async {
    if (_busy) throw StateError('请等待当前活体检测结束后关闭');
    if (_closed) return;
    _closed = true;
    try {
      await _loading;
    } finally {
      try {
        await _session?.close();
      } finally {
        _session = null;
        await _contextSession?.close();
        _contextSession = null;
      }
    }
  }
}
