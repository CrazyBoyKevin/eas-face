import 'dart:math' as math;
import 'package:eas_face/eas_face.dart';
import 'liveness_engine.dart';

enum LivenessStatus { collecting, live, rejected }

class LivenessDecision {
  const LivenessDecision(
    this.status,
    this.acceptedFrames,
    this.observationTime,
  );
  final LivenessStatus status;
  final int acceptedFrames;
  final Duration observationTime;
  bool get passed => status == LivenessStatus.live;
}

/// Temporal confirmation, NOT proof of camera provenance. Use fresh frames and
/// a monotonic capture clock; reset on camera/reference changes or interruption.
/// The verifier additionally binds identity on every frame. If using this class
/// directly with multiple people, maintain a separate session per tracked face.
class PassiveLivenessSession {
  PassiveLivenessSession({
    this.threshold = .9,
    this.minimumFrames = 3,
    this.minimumObservation = const Duration(milliseconds: 600),
    this.minimumInterval = const Duration(milliseconds: 100),
    this.maximumGap = const Duration(milliseconds: 700),
  }) {
    if (!threshold.isFinite ||
        threshold <= .5 ||
        threshold >= 1 ||
        minimumFrames < 2 ||
        minimumObservation <= Duration.zero ||
        minimumInterval <= Duration.zero ||
        maximumGap <= minimumInterval) {
      throw ArgumentError('无效的活体确认参数');
    }
  }

  /// Conservative initial engineering threshold, not business-calibrated.
  final double threshold;
  final int minimumFrames;
  final Duration minimumObservation, minimumInterval, maximumGap;
  Duration? _first, _last;
  FaceDetection? _face;
  int _count = 0;

  void reset() {
    _first = null;
    _last = null;
    _face = null;
    _count = 0;
  }

  LivenessDecision update(LivenessFrameResult frame, Duration capturedAt) {
    if (capturedAt.isNegative) {
      reset();
      throw ArgumentError('时间必须单调递增');
    }
    if (_last != null && capturedAt <= _last!) {
      reset();
      return const LivenessDecision(
        LivenessStatus.collecting,
        0,
        Duration.zero,
      );
    }
    if (!frame.liveScore.isFinite ||
        frame.liveScore < threshold ||
        frame.liveScore > 1) {
      reset();
      return const LivenessDecision(LivenessStatus.rejected, 0, Duration.zero);
    }
    if (_last != null &&
        (capturedAt - _last! > maximumGap || _iou(_face!, frame.face) < .5)) {
      reset();
    }
    if (_last != null && capturedAt - _last! < minimumInterval) {
      // Never report a fresh pass for a frame not added to the observation.
      return LivenessDecision(
        LivenessStatus.collecting,
        _count,
        capturedAt - _first!,
      );
    }
    _first ??= capturedAt;
    _last = capturedAt;
    _face = frame.face;
    _count++;
    final elapsed = capturedAt - _first!;
    return LivenessDecision(
      _count >= minimumFrames && elapsed >= minimumObservation
          ? LivenessStatus.live
          : LivenessStatus.collecting,
      _count,
      elapsed,
    );
  }

  static double _iou(FaceDetection a, FaceDetection b) {
    final intersection =
        math.max(
          0.0,
          math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x),
        ) *
        math.max(
          0.0,
          math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y),
        );
    final union = a.width * a.height + b.width * b.height - intersection;
    return union > 0 ? intersection / union : 0;
  }
}
