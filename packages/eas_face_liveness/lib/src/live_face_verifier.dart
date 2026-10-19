import 'package:eas_face/eas_face.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'liveness_engine.dart';
import 'liveness_session.dart';
import 'liveness_preprocessing.dart';

enum LiveVerificationStatus {
  noFace,
  multipleFaces,
  unusableFace,
  insufficientContext,
  identityMismatch,
  collecting,
  live,
  spoofSuspected,
}

class LiveFaceVerification {
  const LiveFaceVerification({
    required this.status,
    required this.search,
    required this.elapsed,
    this.matchThreshold = defaultThreshold,
    this.liveness,
    this.decision,
  });
  final LiveVerificationStatus status;
  final FaceSearchResult search;
  final double matchThreshold;
  final LivenessFrameResult? liveness;
  final LivenessDecision? decision;

  /// Full processing for this frame; observation time is reported separately.
  final Duration elapsed;
  bool get passed => status == LiveVerificationStatus.live;
  Map<String, Object?> toJson() => {
    'passed': passed,
    'status': status.name,
    'elapsedMs': _ms(elapsed),
    'observationMs': _ms(decision?.observationTime ?? Duration.zero),
    'acceptedFrames': decision?.acceptedFrames ?? 0,
    'comparison': search.best?.toJson(threshold: matchThreshold),
    'liveness': liveness?.toJson(),
  };
  static double _ms(Duration d) =>
      double.parse((d.inMicroseconds / 1000).toStringAsFixed(2));
}

/// Single-person camera verification: same face must match the reference AND
/// pass passive anti-spoofing across fresh frames. More than one detected face
/// resets confirmation; base eas_face's optional multi-face API is unchanged.
/// Takes ownership of supplied engines; close only this verifier after use.
class LiveFaceVerifier {
  LiveFaceVerifier({
    FaceEngine? faceEngine,
    FaceLivenessEngine? livenessEngine,
    PassiveLivenessSession? session,
    this.matchThreshold = defaultThreshold,
  }) : _faceEngine = faceEngine ?? FaceEngine(),
       _livenessEngine = livenessEngine ?? FaceLivenessEngine(),
       _session = session ?? PassiveLivenessSession() {
    if (!matchThreshold.isFinite || matchThreshold <= 0 || matchThreshold > 1) {
      throw ArgumentError.value(matchThreshold, 'matchThreshold');
    }
  }
  final FaceEngine _faceEngine;
  final FaceLivenessEngine _livenessEngine;
  final PassiveLivenessSession _session;
  final double matchThreshold;
  final Stopwatch _clock = Stopwatch()..start();
  Uint8List? _reference;
  int? _width, _height;
  bool _busy = false, _closed = false;
  int _generation = 0;
  Future<void>? _loading;

  Future<void> initialize() {
    if (_closed) throw StateError('验证器已关闭');
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      await _faceEngine.initialize();
      await _livenessEngine.initialize();
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  /// Call immediately on pause, reference/camera change, or leaving the screen.
  /// Invalidates pending processing as well as accumulated confirmation.
  void reset() {
    _generation++;
    _session.reset();
    _width = null;
    _height = null;
  }

  Future<LiveFaceVerification> verifyFrame(
    Uint8List reference,
    img.Image frame,
  ) async {
    if (_closed) throw StateError('验证器已关闭');
    if (_busy) throw StateError('验证正在进行中，请丢弃积压帧');
    _busy = true;
    final watch = Stopwatch()..start();
    final capturedAt = _clock.elapsed;
    try {
      if (!listEquals(_reference, reference)) {
        reset();
        _reference = Uint8List.fromList(reference);
      }
      if (_width != frame.width || _height != frame.height) {
        reset();
        _width = frame.width;
        _height = frame.height;
      }
      final generation = _generation;
      await initialize();
      final search = await _faceEngine.searchImage(reference, frame);
      LiveFaceVerification result(
        LiveVerificationStatus status, [
        LivenessFrameResult? live,
        LivenessDecision? decision,
      ]) => LiveFaceVerification(
        status: status,
        matchThreshold: matchThreshold,
        search: search,
        elapsed: watch.elapsed,
        liveness: live,
        decision: decision,
      );
      if (generation != _generation) {
        return result(LiveVerificationStatus.collecting);
      }
      final candidate = search.best;
      if (search.detectedFaceCount != 1 ||
          candidate == null ||
          candidate.first.faceCount != 1 ||
          !candidate.matches(matchThreshold)) {
        _session.reset();
        return result(
          search.detectedFaceCount == 0
              ? LiveVerificationStatus.noFace
              : search.detectedFaceCount > 1 ||
                  (candidate?.first.faceCount ?? 1) > 1
              ? LiveVerificationStatus.multipleFaces
              : candidate == null
              ? LiveVerificationStatus.unusableFace
              : LiveVerificationStatus.identityMismatch,
        );
      }
      if (availableLivenessContext(frame, candidate.second.detection) < 2.7) {
        _session.reset();
        return result(LiveVerificationStatus.insufficientContext);
      }
      final live = await _livenessEngine.evaluateFrame(
        frame,
        candidate.second.detection,
      );
      if (generation != _generation) {
        return result(LiveVerificationStatus.collecting);
      }
      final decision = _session.update(live, capturedAt);
      return result(
        switch (decision.status) {
          LivenessStatus.collecting => LiveVerificationStatus.collecting,
          LivenessStatus.live => LiveVerificationStatus.live,
          LivenessStatus.rejected => LiveVerificationStatus.spoofSuspected,
        },
        live,
        decision,
      );
    } catch (_) {
      _session.reset();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> close() async {
    if (_busy) throw StateError('请等待当前验证结束后关闭');
    if (_closed) return;
    _closed = true;
    reset();
    _reference = null;
    try {
      await _loading;
    } finally {
      try {
        await _livenessEngine.close();
      } finally {
        await _faceEngine.close();
      }
    }
  }
}
