import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
// Test adapter simulates ONNX outputs, never real identities or private photos.
// ignore: implementation_imports
import 'package:flutter_onnxruntime/src/flutter_onnxruntime_platform_interface.dart';
import 'package:image/image.dart' as img;
import 'package:eas_face/src/face_engine.dart';
import 'package:eas_face/src/face_math.dart';

class TestEngine extends FaceEngine {
  TestEngine({super.compareAllFaces});
  @override
  Future<OrtSession> createModelSession(String assetPath) async =>
      OrtSession.fromMap({
        'sessionId': assetPath.contains('yunet') ? 'detector' : 'recognizer',
        'inputNames': ['input'],
        'outputNames': ['output'],
      });
}

class FakeRuntime extends FlutterOnnxruntimePlatform {
  final detections = Queue<Map<String, List<double>>>();
  final embeddings = Queue<List<double>>();
  final tensors = <String, List<double>>{};
  final recognitionInputs = <List<double>>[];
  int detectorRuns = 0, recognizerRuns = 0, next = 0;
  bool failRecognition = false;

  void addFaces(List<FaceDetection> faces, List<int> featureIds) {
    detections.add(detectorOutput(faces));
    for (final id in featureIds) {
      final vector = List<double>.filled(256, 0)..[id] = 1;
      // Standard and auxiliary inference, both always enabled.
      embeddings.addAll([vector, vector]);
    }
  }

  @override
  Future<Map<String, dynamic>> createOrtValue(
    String type,
    dynamic data,
    List<int> shape,
  ) async {
    final id = 'v${next++}';
    tensors[id] = (data as List).map((v) => (v as num).toDouble()).toList();
    return {'valueId': id, 'dataType': 'float32', 'shape': shape};
  }

  @override
  Future<Map<String, dynamic>> runInference(
    String sessionId,
    Map<String, OrtValue> inputs, {
    Map<String, dynamic>? runOptions,
  }) async {
    final Map<String, List<double>> values;
    if (sessionId == 'detector') {
      detectorRuns++;
      values = detections.removeFirst();
    } else {
      recognizerRuns++;
      if (failRecognition) throw StateError('Simulated runtime failure');
      recognitionInputs.add(List.of(tensors[inputs.values.single.id]!));
      values = {'output': embeddings.removeFirst()};
    }
    return {
      for (final entry in values.entries) entry.key: await output(entry.value),
    };
  }

  Future<List<Object>> output(List<double> values) async {
    final id = 'v${next++}';
    tensors[id] = values;
    return [
      id,
      'float32',
      [values.length],
    ];
  }

  @override
  Future<Map<String, dynamic>> getOrtValueData(String id) async => {
    'data': tensors[id]!,
  };
  @override
  Future<void> releaseOrtValue(String id) async {
    tensors.remove(id);
  }

  @override
  Future<void> closeSession(String id) async {}
}

FaceDetection face(double x, double size) => FaceDetection(
  x: x,
  y: 40,
  width: size,
  height: size,
  score: .99,
  landmarks:
      canonicalLandmarks
          .map((p) => FacePoint(x + p.x * size / 128, 40 + p.y * size / 128))
          .toList(),
);

Map<String, List<double>> detectorOutput(List<FaceDetection> faces) {
  final result = <String, List<double>>{};
  for (final stride in [8, 16, 32]) {
    final count = (640 ~/ stride) * (640 ~/ stride);
    result['cls_$stride'] = List.filled(count, 0);
    result['obj_$stride'] = List.filled(count, 0);
    result['bbox_$stride'] = List.filled(count * 4, 0);
    result['kps_$stride'] = List.filled(count * 10, 0);
  }
  for (var i = 0; i < faces.length; i++) {
    final f = faces[i];
    result['cls_8']![i] = result['obj_8']![i] = f.score;
    result['bbox_8']!.setRange(i * 4, i * 4 + 4, [
      (f.x + f.width / 2) / 8 - i,
      (f.y + f.height / 2) / 8,
      math.log(f.width / 8),
      math.log(f.height / 8),
    ]);
    result['kps_8']!.setRange(i * 10, i * 10 + 10, [
      for (final p in f.landmarks) ...[p.x / 8 - i, p.y / 8],
    ]);
  }
  return result;
}

Uint8List photo(int value) {
  final image = img.Image(width: 640, height: 640);
  img.fill(image, color: img.ColorRgb8(value, 100, 150));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlutterOnnxruntimePlatform previous;
  late FakeRuntime runtime;
  final large = face(20, 240), small = face(360, 180), tiny = face(570, 40);
  final a = photo(50), b = photo(80);
  setUp(() {
    previous = FlutterOnnxruntimePlatform.instance;
    runtime = FakeRuntime();
    FlutterOnnxruntimePlatform.instance = runtime;
  });
  tearDown(() {
    expect(
      runtime.tensors,
      isEmpty,
      reason: 'All ONNX values must be released',
    );
    FlutterOnnxruntimePlatform.instance = previous;
  });

  test(
    'best pair is global maximum and threshold may change after comparison',
    () {
      FaceSample sample(List<double> vector) => FaceSample(
        preview: Uint8List(0),
        alignedPreview: Uint8List(0),
        embedding: vector,
        detection: small,
        width: 640,
        height: 640,
        faceCount: 2,
      );
      final first = [
        sample([1, 0]),
        sample([0, 1]),
      ];
      final second = [
        sample([.6, .8]),
        sample([.1, .9]),
      ];
      final pair = bestFacePair(first, second);
      expect(identical(pair.$1, first[1]), isTrue);
      expect(identical(pair.$2, second[1]), isTrue);
      final result = FaceComparison(pair.$1, pair.$2, pair.$3, Duration.zero);
      for (final threshold in [.6, .8, .99, 1.0]) {
        final any = first.any(
          (a) => second.any(
            (b) => FaceComparison(
              a,
              b,
              cosineSimilarity(a.embedding, b.embedding),
              Duration.zero,
            ).matches(threshold),
          ),
        );
        expect(result.matches(threshold), any);
        expect(result.toJson(threshold: threshold)['passed'], any);
      }
      expect(() => bestFacePair([], second), throwsFormatException);
    },
  );

  test(
    'default remains largest-only, with automatic achromatic auxiliary',
    () async {
      final engine = TestEngine();
      expect(engine.compareAllFaces, isFalse);
      runtime.addFaces([small, large], [0]);
      runtime.addFaces([small, large], [1]);
      final result = await engine.compare(a, b);
      expect(result.matches(.60), isFalse);
      expect(result.first.detection.x, closeTo(large.x, .001));
      expect(runtime.recognizerRuns, 4);
      final auxiliary = runtime.recognitionInputs[1];
      const n = 128 * 128;
      expect(auxiliary.sublist(0, n), auxiliary.sublist(n, n * 2));
      expect(auxiliary.sublist(0, n), auxiliary.sublist(n * 2));
      expect(runtime.recognitionInputs[0], isNot(auxiliary));
      await engine.close();
    },
  );

  test(
    'all pairs finds smaller faces on both sides, result JSON follows winner',
    () async {
      final engine = TestEngine(compareAllFaces: true);
      runtime.addFaces([small, large], [0, 2]);
      runtime.addFaces([large, small], [1, 2]);
      final result = await engine.compare(a, b);
      expect(result.matches(.60), isTrue);
      expect(result.cosine, closeTo(1, 1e-9));
      expect(result.first.detection.x, closeTo(small.x, .001));
      expect(result.second.detection.x, closeTo(small.x, .001));
      expect(result.first.faceCount, 2);
      expect(result.toJson()['first'], result.first.toJson());
      expect((result.first.toJson()['faceBox'] as Map)['x'], 360);
      expect(result.first.alignedPreview, isNotEmpty);
      expect(runtime.detectorRuns, 2);
      expect(runtime.recognizerRuns, 8);
      final cached = await engine.compare(Uint8List.fromList(a), b);
      expect(identical(cached.first, result.first), isTrue);
      expect(identical(cached.second, result.second), isTrue);
      expect(runtime.recognizerRuns, 8);
      engine.retainCachedPhotos([]);
      runtime.addFaces([large, small], [0, 2]);
      runtime.addFaces([large, small], [1, 2]);
      final fresh = await engine.compare(a, b);
      expect(identical(fresh.first, result.first), isFalse);
      expect(fresh.cosine, result.cosine);
      expect(runtime.recognizerRuns, 16);
      await engine.close();
    },
  );

  for (final groupFirst in [true, false]) {
    test('single versus group works with groupFirst=$groupFirst', () async {
      final engine = TestEngine(compareAllFaces: true);
      runtime.addFaces(
        groupFirst ? [large, small] : [large],
        groupFirst ? [0, 1] : [1],
      );
      runtime.addFaces(
        groupFirst ? [large] : [large, small],
        groupFirst ? [1] : [0, 1],
      );
      final result = await engine.compare(a, b);
      expect(result.matches(.60), isTrue);
      expect(
        (groupFirst ? result.first : result.second).detection.x,
        closeTo(360, .001),
      );
      expect(runtime.recognizerRuns, 6);
      await engine.close();
    });
  }

  test(
    'no matching pairs fails; equal scores select first ranked pair',
    () async {
      final engine = TestEngine(compareAllFaces: true);
      runtime.addFaces([large, small], [0, 1]);
      runtime.addFaces([small, large], [2, 3]);
      final result = await engine.compare(a, b);
      expect(result.matches(.60), isFalse);
      expect(result.first.detection.x, closeTo(20, .001));
      expect(result.second.detection.x, closeTo(20, .001));
      expect(runtime.recognizerRuns, 8);
      await engine.close();
    },
  );

  test(
    'too-small detections are skipped but counted; no usable face throws',
    () async {
      final engine = TestEngine(compareAllFaces: true);
      runtime.addFaces([tiny, small], [0]);
      runtime.addFaces([large], [0]);
      final result = await engine.compare(a, b);
      expect(result.matches(.60), isTrue);
      expect(result.first.faceCount, 2);
      engine.retainCachedPhotos([]);
      runtime.addFaces([tiny], []);
      await expectLater(engine.compare(a, b), throwsA(isA<FormatException>()));
      runtime.addFaces([], []);
      await expectLater(engine.compare(a, b), throwsA(isA<FormatException>()));
      await engine.close();
    },
  );

  test('runtime failures propagate and busy state resets for retry', () async {
    final engine = TestEngine(compareAllFaces: true);
    runtime.addFaces([large], []);
    runtime.failRecognition = true;
    await expectLater(engine.compare(a, b), throwsStateError);
    runtime.failRecognition = false;
    runtime.addFaces([large], [0]);
    runtime.addFaces([large], [0]);
    expect((await engine.compare(a, b)).matches(.60), isTrue);
    await engine.close();
  });

  test(
    'raw frame all-pairs matches smaller target and never caches frame',
    () async {
      final engine = TestEngine(compareAllFaces: true);
      runtime.addFaces([large, small], [0, 2]);
      runtime.addFaces([large, small], [1, 2]);
      final image = img.decodeImage(b)!;
      final result = await engine.compareImage(a, image);
      expect(result.matches(.60), isTrue);
      expect(result.first.detection.x, closeTo(360, .001));
      expect(result.second.detection.x, closeTo(360, .001));
      expect(result.second.preview, isEmpty);
      runtime.addFaces([large, small], [1, 2]);
      await engine.compareImage(a, image);
      expect(runtime.detectorRuns, 3);
      await engine.close();
    },
  );

  test(
    'search API still exposes all candidates and blank search is empty',
    () async {
      final engine = TestEngine();
      runtime.addFaces([large], [1]);
      runtime.addFaces([large, small], [0, 1]);
      final result = await engine.searchImage(a, img.decodeImage(b)!);
      expect(result.candidates.length, 2);
      expect(result.matches(.60).length, 1);
      expect(result.best!.second.detection.x, closeTo(360, .001));
      runtime.addFaces([], []);
      expect((await engine.searchImage(a, img.decodeImage(b)!)).best, isNull);
      await engine.close();
    },
  );
  test(
    'extraction-only API needs no reference, bounds faces and returns empty frames',
    () async {
      final engine = TestEngine();
      runtime.addFaces([large, small, tiny], [0, 1]);
      final result = await engine.extractImage(img.decodeImage(b)!);
      expect(result.detectedFaceCount, 3);
      expect(result.faces.length, 2);
      expect(
        result.faces.every(
          (f) => f.embedding.length == 256 && f.preview.isEmpty,
        ),
        isTrue,
      );
      runtime.addFaces([large, small], [0]);
      final limited = await engine.extractImage(
        img.decodeImage(b)!,
        maxFaces: 1,
      );
      expect(limited.faces.length, 1);
      expect(limited.detectedFaceCount, 2);
      runtime.addFaces([], []);
      expect((await engine.extractImage(img.decodeImage(b)!)).faces, isEmpty);
      await expectLater(
        engine.extractImage(img.decodeImage(b)!, maxFaces: 9),
        throwsArgumentError,
      );
      await engine.close();
    },
  );
}
