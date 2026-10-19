import 'dart:async';
import 'dart:typed_data';
import 'package:eas_face/eas_face.dart';
import 'package:eas_face_liveness/eas_face_liveness.dart';
import 'package:eas_face_liveness/src/liveness_preprocessing.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
// ignore: implementation_imports
import 'package:flutter_onnxruntime/src/flutter_onnxruntime_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

FaceDetection box([double x = 50]) => FaceDetection(
  x: x,
  y: 60,
  width: 100,
  height: 100,
  score: .99,
  landmarks: const [],
);
LivenessFrameResult scored(double score, [double x = 50]) =>
    LivenessFrameResult(
      liveScore: score,
      face: box(x),
      preprocessTime: Duration.zero,
      inferenceTime: Duration.zero,
      elapsed: Duration.zero,
    );
img.Image pixels() =>
    img.Image(width: 640, height: 480)..clear(img.ColorRgb8(17, 89, 201));

class FakeOrt extends FlutterOnnxruntimePlatform {
  final values = <String, List<double>>{};
  List<double> logits = [0, 9, 0];
  List<double>? contextLogits;
  bool failContext = false;
  int next = 0;
  bool fail = false, duplicate = false;
  List<int>? shape;
  List<double>? input;
  int closed = 0;
  @override
  Future<Map<String, dynamic>> createOrtValue(
    String type,
    dynamic data,
    List<int> dims,
  ) async {
    shape = dims;
    input = (data as List).cast<double>();
    final id = 'v${next++}';
    values[id] = input!;
    return {'valueId': id, 'dataType': 'float32', 'shape': dims};
  }

  @override
  Future<Map<String, dynamic>> runInference(
    String sessionId,
    Map<String, OrtValue> inputs, {
    Map<String, dynamic>? runOptions,
  }) async {
    if (fail || (sessionId == 'context' && failContext)) {
      throw StateError('runtime failure');
    }
    final id = duplicate ? inputs.values.single.id : 'v${next++}';
    values[id] = sessionId == 'context' ? contextLogits ?? logits : logits;
    return {
      'logits': [
        id,
        'float32',
        [1, 3],
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getOrtValueData(String valueId) async => {
    'data': values[valueId]!,
  };
  @override
  Future<void> releaseOrtValue(String valueId) async {
    values.remove(valueId);
  }

  @override
  Future<void> closeSession(String sessionId) async {
    closed++;
  }
}

class TestEngine extends FaceLivenessEngine {
  bool failLoad = false;
  int loads = 0;
  bool failContextLoad = false;
  @override
  Future<OrtSession> createContextModelSession() async {
    if (failContextLoad) throw StateError('context load failure');
    return OrtSession.fromMap({
      'sessionId': 'context',
      'inputNames': ['input'],
      'outputNames': ['logits'],
    });
  }

  @override
  Future<OrtSession> createModelSession() async {
    loads++;
    if (failLoad) throw StateError('load failure');
    return OrtSession.fromMap({
      'sessionId': 'live',
      'inputNames': ['input'],
      'outputNames': ['logits'],
    });
  }
}

FaceSample sample({int count = 1}) => FaceSample(
  preview: Uint8List(0),
  alignedPreview: Uint8List(0),
  embedding: [1, 0],
  detection: box(),
  width: 320,
  height: 240,
  faceCount: count,
);

class FakeFaces extends FaceEngine {
  int count = 1, referenceCount = 1;
  double score = 1;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> close() async {}
  @override
  Future<FaceSearchResult> searchImage(
    Uint8List reference,
    img.Image frame,
  ) async {
    await pending?.future;
    if (fail) throw StateError('identity failed');
    return FaceSearchResult(
      [
        if (count > 0)
          FaceComparison(
            sample(count: referenceCount),
            sample(),
            score,
            Duration.zero,
          ),
      ],
      count,
      Duration.zero,
    );
  }
}

class FakeLive extends FaceLivenessEngine {
  int calls = 0;
  double score = .99;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> close() async {}
  @override
  Future<LivenessFrameResult> evaluateFrame(
    img.Image frame,
    FaceDetection face,
  ) async {
    calls++;
    return scored(score);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('BGR planes preserve 0..255 values, no normalization or correction', () {
    final input = prepareLivenessInput((pixels(), box()));
    expect(input.length, 19200);
    expect(input.take(6400), everyElement(201));
    expect(input.skip(6400).take(6400), everyElement(89));
    expect(input.skip(12800), everyElement(17));
  });
  test('context crop at image edges remains bounded and rejects bad boxes', () {
    expect(prepareLivenessInput((pixels(), box(0))).length, 19200);
    for (final x in [-1.0, double.nan, double.infinity, 600.0]) {
      expect(
        () => prepareLivenessInput((pixels(), box(x))),
        throwsFormatException,
      );
    }
  });
  test(
    'requires both minimum count and time, not just a high single score',
    () {
      final s = PassiveLivenessSession();
      expect(s.update(scored(.99), Duration.zero).passed, isFalse);
      expect(
        s.update(scored(.99), const Duration(milliseconds: 300)).passed,
        isFalse,
      );
      expect(
        s.update(scored(.99), const Duration(milliseconds: 600)).passed,
        isTrue,
      );
      expect(
        s.update(scored(.1), const Duration(milliseconds: 800)).status,
        LivenessStatus.rejected,
      );
      expect(
        s.update(scored(.99), const Duration(milliseconds: 1000)).passed,
        isFalse,
      );
    },
  );
  test('duplicate or reversed timestamps invalidate accumulated evidence', () {
    final s = PassiveLivenessSession();
    s.update(scored(.99), Duration.zero);
    s.update(scored(.99), const Duration(milliseconds: 300));
    expect(
      s.update(scored(.99), const Duration(milliseconds: 300)).acceptedFrames,
      0,
    );
    expect(
      s.update(scored(.99), const Duration(milliseconds: 600)).passed,
      isFalse,
    );
  });
  test('fast frames do not inflate count or pass prematurely', () {
    final s = PassiveLivenessSession();
    s.update(scored(.99), Duration.zero);
    expect(
      s.update(scored(.99), const Duration(milliseconds: 1)).acceptedFrames,
      1,
    );
    expect(
      s.update(scored(.99), const Duration(milliseconds: 600)).passed,
      isFalse,
    );
  });
  test('tracking jump, gaps and explicit resets restart confirmation', () {
    for (final kind in ['jump', 'gap', 'reset']) {
      final s = PassiveLivenessSession();
      s.update(scored(.99), Duration.zero);
      s.update(scored(.99), const Duration(milliseconds: 300));
      if (kind == 'reset') s.reset();
      final result = s.update(
        scored(.99, kind == 'jump' ? 210 : 50),
        Duration(milliseconds: kind == 'gap' ? 1200 : 600),
      );
      expect(result.passed, isFalse);
      expect(result.acceptedFrames, 1);
    }
  });
  test('invalid scores and settings cannot pass', () {
    for (final score in [double.nan, double.infinity, -1.0, 1.1]) {
      expect(
        PassiveLivenessSession().update(scored(score), Duration.zero).passed,
        isFalse,
      );
    }
    expect(() => PassiveLivenessSession(threshold: .1), throwsArgumentError);
    expect(() => PassiveLivenessSession(minimumFrames: 1), throwsArgumentError);
  });
  group('native runtime adapter', () {
    late FakeOrt runtime;
    late FlutterOnnxruntimePlatform original;
    late TestEngine engine;
    setUp(() {
      original = FlutterOnnxruntimePlatform.instance;
      runtime = FakeOrt();
      FlutterOnnxruntimePlatform.instance = runtime;
      engine = TestEngine();
    });
    tearDown(() async {
      await engine.close();
      FlutterOnnxruntimePlatform.instance = original;
    });
    test('class 1 softmax, lazy session reuse and disposal', () async {
      final result = await engine.evaluateFrame(pixels(), box());
      expect(result.liveScore, closeTo(.99975324, 1e-6));
      expect(runtime.shape, [1, 3, 80, 80]);
      expect(runtime.input!.first, 201);
      expect(runtime.values, isEmpty);
      await engine.evaluateFrame(pixels(), box());
      expect(engine.loads, 1);
      runtime.logits = [1000, 1001, 1000];
      expect(
        (await engine.evaluateFrame(pixels(), box())).liveScore,
        closeTo(.5761169, 1e-6),
      );
    });
    test(
      'bad outputs/runtime errors propagate and release input tensors',
      () async {
        runtime.fail = true;
        await expectLater(
          engine.evaluateFrame(pixels(), box()),
          throwsStateError,
        );
        expect(runtime.values, isEmpty);
        runtime.fail = false;
        for (final logits in [
          [double.nan, 0.0, 0.0],
          [0.0],
          [0.0, double.infinity, 0.0],
        ]) {
          runtime.logits = logits;
          await expectLater(
            engine.evaluateFrame(pixels(), box()),
            throwsStateError,
          );
          expect(runtime.values, isEmpty);
        }
        runtime.logits = [0, 9, 0];
        runtime.duplicate = true;
        await expectLater(
          engine.evaluateFrame(pixels(), box()),
          throwsStateError,
        );
        expect(runtime.values, isEmpty);
      },
    );
    test('concurrent inference and close while busy rejected', () async {
      final pending = engine.evaluateFrame(pixels(), box());
      await expectLater(
        engine.evaluateFrame(pixels(), box()),
        throwsStateError,
      );
      await expectLater(engine.close(), throwsStateError);
      await pending;
      await engine.close();
      expect(engine.isReady, isFalse);
      await expectLater(
        engine.evaluateFrame(pixels(), box()),
        throwsStateError,
      );
      expect(runtime.closed, 2);
    });
    test('failed initialization can be retried', () async {
      engine.failLoad = true;
      await expectLater(engine.initialize(), throwsStateError);
      engine.failLoad = false;
      await engine.initialize();
      expect(engine.loads, 2);
    });
    test(
      'both models must agree; a high texture score cannot mask context rejection',
      () async {
        runtime.contextLogits = [9, 0, 0];
        final result = await engine.evaluateFrame(pixels(), box());
        expect(result.modelScores['texture2_7'], greaterThan(.99));
        expect(result.modelScores['context4'], lessThan(.001));
        expect(result.liveScore, result.modelScores['context4']);
        expect(
          PassiveLivenessSession().update(result, Duration.zero).status,
          LivenessStatus.rejected,
        );
        expect(runtime.values, isEmpty);
      },
    );
    test('context model errors fail closed and release tensors', () async {
      runtime.failContext = true;
      await expectLater(
        engine.evaluateFrame(pixels(), box()),
        throwsStateError,
      );
      expect(runtime.values, isEmpty);
      runtime.failContext = false;
      expect(
        (await engine.evaluateFrame(pixels(), box())).modelScores.length,
        2,
      );
    });
    test(
      'partial model initialization is not ready and retry reuses first session',
      () async {
        engine.failContextLoad = true;
        await expectLater(engine.initialize(), throwsStateError);
        expect(engine.isReady, isFalse);
        engine.failContextLoad = false;
        await engine.initialize();
        expect(engine.isReady, isTrue);
        expect(engine.loads, 1);
      },
    );
  });
  test(
    'verifier only checks liveness on the same uniquely matching camera face',
    () async {
      final faces = FakeFaces(), live = FakeLive();
      final verifier = LiveFaceVerifier(
        faceEngine: faces,
        livenessEngine: live,
      );
      final ref = Uint8List.fromList([1]);
      faces.count = 0;
      expect(
        (await verifier.verifyFrame(ref, pixels())).status,
        LiveVerificationStatus.noFace,
      );
      faces.count = 2;
      expect(
        (await verifier.verifyFrame(ref, pixels())).status,
        LiveVerificationStatus.multipleFaces,
      );
      faces.count = 1;
      faces.referenceCount = 2;
      expect(
        (await verifier.verifyFrame(ref, pixels())).status,
        LiveVerificationStatus.multipleFaces,
      );
      faces.referenceCount = 1;
      faces.score = -1;
      expect(
        (await verifier.verifyFrame(ref, pixels())).status,
        LiveVerificationStatus.identityMismatch,
      );
      expect(live.calls, 0);
      faces.score = 1;
      live.score = .1;
      expect(
        (await verifier.verifyFrame(ref, pixels())).status,
        LiveVerificationStatus.spoofSuspected,
      );
      live.score = .99;
      expect((await verifier.verifyFrame(ref, pixels())).passed, isFalse);
      await verifier.close();
    },
  );
  test(
    'joint pass and reset on reference, resolution, absence and errors',
    () async {
      final faces = FakeFaces(), live = FakeLive();
      final verifier = LiveFaceVerifier(
        faceEngine: faces,
        livenessEngine: live,
        matchThreshold: .7,
        session: PassiveLivenessSession(
          minimumObservation: const Duration(milliseconds: 2),
          minimumInterval: const Duration(microseconds: 1),
          maximumGap: const Duration(seconds: 5),
        ),
      );
      final ref = Uint8List.fromList([1]);
      Future<LiveFaceVerification> step() async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return verifier.verifyFrame(ref, pixels());
      }

      await step();
      await step();
      final passed = await step();
      expect(passed.passed, isTrue);
      expect((passed.toJson()['comparison'] as Map)['thresholdPercent'], 70);
      ref[0] = 2; // Even in-place byte mutation invalidates prior confirmation.
      expect((await step()).passed, isFalse);
      await step();
      expect((await step()).passed, isTrue);
      expect(
        (await verifier.verifyFrame(
          ref,
          img.Image(width: 400, height: 300),
        )).passed,
        isFalse,
      );
      faces.count = 0;
      await step();
      faces.count = 1;
      expect((await step()).passed, isFalse);
      await step();
      expect((await step()).passed, isTrue);
      faces.fail = true;
      await expectLater(step(), throwsStateError);
      faces.fail = false;
      expect((await step()).passed, isFalse);
      await verifier.close();
      await expectLater(step(), throwsStateError);
    },
  );
  test(
    'reset while inference pending invalidates result and busy guard rejects queue',
    () async {
      final faces = FakeFaces()..pending = Completer<void>();
      final live = FakeLive();
      final verifier = LiveFaceVerifier(
        faceEngine: faces,
        livenessEngine: live,
      );
      final ref = Uint8List(1);
      final work = verifier.verifyFrame(ref, pixels());
      await Future<void>.delayed(Duration.zero);
      await expectLater(verifier.verifyFrame(ref, pixels()), throwsStateError);
      await expectLater(verifier.close(), throwsStateError);
      verifier.reset();
      faces.pending!.complete();
      expect((await work).passed, isFalse);
      expect(live.calls, 0);
      await verifier.close();
    },
  );
}
