import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'face_math.dart';
import 'image_tensor.dart';
import 'face_score.dart';
import 'photo_cache.dart';
import 'document_tolerance.dart';
import 'document_photometric.dart';
import 'licenses.dart';
export 'face_score.dart';

const maxFileBytes = 15 * 1024 * 1024;

double _twoDecimals(double value) => double.parse(value.toStringAsFixed(2));

// Keep numeric JSON types while preserving two decimal places in copied text.
String _formatResultJson(
  Object? value, [
  int depth = 0,
  bool twoDecimals = false,
]) {
  final indent = '  ' * depth, childIndent = '  ' * (depth + 1);
  // JavaScript represents integral doubles and ints identically; use the
  // summary field's position rather than runtime type to format decimals.
  if (value is num) {
    return twoDecimals ? value.toStringAsFixed(2) : value.toString();
  }
  if (value is Map<String, Object>) {
    if (value.isEmpty) return '{}';
    final fields = value.entries.map(
      (entry) =>
          '$childIndent${jsonEncode(entry.key)}: ${_formatResultJson(entry.value, depth + 1, depth == 0 && entry.value is num)}',
    );
    return '{\n${fields.join(',\n')}\n$indent}';
  }
  if (value is List) {
    if (value.isEmpty) return '[]';
    final items = value.map(
      (item) => '$childIndent${_formatResultJson(item, depth + 1)}',
    );
    return '[\n${items.join(',\n')}\n$indent]';
  }
  return jsonEncode(value);
}

class FaceSample {
  const FaceSample({
    required this.preview,
    required this.alignedPreview,
    required this.embedding,
    required this.detection,
    required this.width,
    required this.height,
    required this.faceCount,
  });
  final Uint8List preview, alignedPreview;
  final List<double> embedding;
  final FaceDetection detection;
  final int width, height, faceCount;

  /// Only the selected face box and five landmarks, in oriented source pixels.
  Map<String, Object> toJson() => {
    'faceBox': {
      'x': detection.x.round(),
      'y': detection.y.round(),
      'width': detection.width.round(),
      'height': detection.height.round(),
    },
    'landmarks': _pointsJson(detection.landmarks),
  };

  static List<Map<String, Object>> _pointsJson(List<FacePoint> points) {
    const names = [
      'imageLeftEye',
      'imageRightEye',
      'nose',
      'imageLeftMouth',
      'imageRightMouth',
    ];
    return [
      for (var i = 0; i < points.length; i++)
        {'name': names[i], 'x': points[i].x.round(), 'y': points[i].y.round()},
    ];
  }

  /// Pixel dimensions of the aligned PNG returned by the engine.
  int get alignedWidth => alignedFaceSize;
  int get alignedHeight => alignedFaceSize;

  /// Detected landmarks mapped into [alignedPreview], in pixel coordinates.
  /// Origin: top-left; x increases rightward, y increases downward.
  /// Order: image-left eye, image-right eye, nose, image-left/right mouth.
  /// Uses the same transform as the crop, not fixed template coordinates.
  List<FacePoint> get alignedLandmarks {
    final transform = fitRecognitionAlignment(detection.landmarks);
    return List<FacePoint>.unmodifiable(
      detection.landmarks.map(transform.apply),
    );
  }
}

class FaceComparison {
  const FaceComparison(this.first, this.second, this.cosine, this.elapsed);
  final FaceSample first, second;
  final double cosine;
  final Duration elapsed;
  double get likeness => likenessScore(cosine);

  /// Threshold is on the display scale, not the raw cosine scale.
  bool matches(double threshold) => likeness >= threshold;

  Map<String, Object> toJson({double threshold = defaultThreshold}) => {
    'likenessPercent': _twoDecimals(likeness * 100),
    'thresholdPercent': _twoDecimals(threshold * 100),
    'passed': matches(threshold),
    'elapsedMs': _twoDecimals(elapsed.inMicroseconds / 1000),
    'first': first.toJson(),
    'second': second.toJson(),
  };

  /// Formatted JSON with two decimal places and integer pixel coordinates.
  String toJsonString({double threshold = defaultThreshold}) =>
      _formatResultJson(toJson(threshold: threshold));
}

/// Exhaustive Cartesian comparison. Stable first pair wins exact score ties.
/// Internal helper also exercised with synthetic feature vectors in tests.
@visibleForTesting
(FaceSample, FaceSample, double) bestFacePair(
  List<FaceSample> first,
  List<FaceSample> second,
) {
  if (first.isEmpty || second.isEmpty) {
    throw const FormatException('没有可用于比对的人脸');
  }
  FaceSample a = first.first, b = second.first;
  var best = double.negativeInfinity;
  for (final left in first) {
    for (final right in second) {
      final score = cosineSimilarity(left.embedding, right.embedding);
      if (score > best) {
        best = score;
        a = left;
        b = right;
      }
    }
  }
  return (a, b, best);
}

/// All usable faces, ranked by raw cosine similarity to one reference photo.
/// [best] is only a candidate; callers must apply a threshold and ambiguity policy.
class FaceSearchResult {
  FaceSearchResult(
    List<FaceComparison> candidates,
    this.detectedFaceCount,
    this.elapsed,
  ) : candidates = List.unmodifiable(candidates);
  final List<FaceComparison> candidates;
  final int detectedFaceCount;
  final Duration elapsed;
  FaceComparison? get best => candidates.isEmpty ? null : candidates.first;
  int get skippedFaceCount => detectedFaceCount - candidates.length;
  List<FaceComparison> matches(double threshold) =>
      candidates.where((candidate) => candidate.matches(threshold)).toList();
}

/// All usable faces from one raw frame, before any identity comparison.
class FaceFrameSamples {
  FaceFrameSamples(List<FaceSample> faces, this.detectedFaceCount)
    : faces = List.unmodifiable(faces);
  final List<FaceSample> faces;
  final int detectedFaceCount;
}

/// Contains no HTTP client, image upload or persistent biometric store.
/// Supports Android and iOS with packaged native model assets.
class FaceEngine {
  /// Compare only the largest faces by default. When enabled, compare all
  /// usable face pairs and return the highest-scoring pair, even if it fails.
  /// Geometric and color/lighting assistance are always applied internally.
  FaceEngine({this.compareAllFaces = false});
  final bool compareAllFaces;

  final _cache = PhotoCache<List<FaceSample>>();
  OrtSession? _detector, _recognizer;
  Future<void>? _loading;
  bool _busy = false;
  bool get isReady => _detector != null && _recognizer != null;

  Future<void> initialize() => _loading ??= _load();

  /// Native model-session factory. Hosts may override for their own runtime.
  @protected
  Future<OrtSession> createModelSession(String assetPath) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError('eas_face 仅支持 Android 和 iOS');
    }
    return OnnxRuntime().createSessionFromAsset(
      assetPath,
      options: OrtSessionOptions(intraOpNumThreads: 2, interOpNumThreads: 1),
    );
  }

  Future<void> _load() async {
    registerSdkLicenses();
    try {
      const prefix = 'packages/eas_face/assets/models/';
      _detector = await createModelSession(
        '${prefix}face_detection_yunet_2023mar.onnx',
      );
      _recognizer = await createModelSession(
        '${prefix}face-reidentification-retail-0095.onnx',
      );
    } catch (_) {
      await _detector?.close();
      await _recognizer?.close();
      _detector = null;
      _recognizer = null;
      _loading = null;
      rethrow;
    }
  }

  Future<Map<String, List<double>>> _infer(
    OrtSession session,
    Float32List data,
    List<int> shape,
  ) async {
    // Reject duplicate tensor handles before consuming inference outputs.
    for (var attempt = 0; attempt < 3; attempt++) {
      final input = await OrtValue.fromList(data, shape);
      Map<String, OrtValue>? outputs;
      try {
        outputs = await session.run({session.inputNames.single: input});
        final ids = [input.id, ...outputs.values.map((value) => value.id)];
        if (ids.toSet().length != ids.length) {
          if (attempt == 2) {
            throw StateError('ONNX runtime returned duplicate tensor handles');
          }
          continue;
        }
        final values = <String, List<double>>{};
        for (final entry in outputs.entries) {
          values[entry.key] =
              (await entry.value.asFlattenedList())
                  .map((v) => (v as num).toDouble())
                  .toList();
        }
        return values;
      } finally {
        final tensors = {input.id: input};
        for (final tensor in outputs?.values ?? <OrtValue>[]) {
          tensors[tensor.id] = tensor;
        }
        for (final tensor in tensors.values) {
          await tensor.dispose();
        }
      }
    }
    throw StateError('ONNX inference did not return outputs');
  }

  Future<FaceComparison> compare(
    Uint8List first,
    Uint8List second, {
    void Function(String)? onProgress,
  }) async {
    if (_busy) throw StateError('比对正在进行中');
    _busy = true;
    final stopwatch = Stopwatch()..start();
    try {
      await initialize();
      _cache.retain([first, second]);
      onProgress?.call('正在分析第一张照片…');
      final a = await _extractCachedFaces(first, '第一张照片');
      onProgress?.call('正在分析第二张照片…');
      final b = await _extractCachedFaces(second, '第二张照片');
      final pair = bestFacePair(a, b);
      return FaceComparison(pair.$1, pair.$2, pair.$3, stopwatch.elapsed);
    } finally {
      _busy = false;
    }
  }

  /// Compare a cached reference photo with an upright, unmirrored camera image.
  /// Camera pixels are never JPEG encoded or retained in the photo cache.
  /// Uses the same models, alignment and score as [compare]. Calls are serial.
  Future<FaceComparison> compareImage(
    Uint8List reference,
    img.Image frame,
  ) async {
    if (_busy) throw StateError('比对正在进行中');
    _busy = true;
    final stopwatch = Stopwatch()..start();
    try {
      await initialize();
      _cache.retain([reference]);
      final first = await _extractCachedFaces(reference, '参考照片');
      final prepared = await compute(_prepareDecodedImage, frame);
      final second = await _extractPreparedFaces(
        prepared,
        Uint8List(0),
        '相机画面',
      );
      final pair = bestFacePair(first, second);
      return FaceComparison(pair.$1, pair.$2, pair.$3, stopwatch.elapsed);
    } finally {
      _busy = false;
    }
  }

  /// Detect once, then compare every usable face against the cached reference.
  /// Explicit search API: reference always uses its largest usable face.
  /// Independent of compareAllFaces; returns all frame candidates.
  /// Faces below the minimum size or with invalid alignment are skipped.
  /// Runtime errors propagate; they are never treated as a non-match.
  Future<FaceSearchResult> searchImage(
    Uint8List reference,
    img.Image frame,
  ) async {
    if (_busy) throw StateError('比对正在进行中');
    _busy = true;
    final stopwatch = Stopwatch()..start();
    try {
      await initialize();
      _cache.retain([reference]);
      final first = (await _extractCachedFaces(reference, '参考照片')).first;
      final prepared = await compute(_prepareDecodedImage, frame);
      final detected = await _detectPrepared(prepared);
      final candidates = <FaceComparison>[];
      for (final detection in detected) {
        final FaceSample second;
        try {
          second = await _extractDetected(
            prepared,
            Uint8List(0),
            detection,
            detected.length,
          );
        } on FormatException {
          continue;
        }
        candidates.add(
          FaceComparison(
            first,
            second,
            cosineSimilarity(first.embedding, second.embedding),
            stopwatch.elapsed,
          ),
        );
      }
      candidates.sort((a, b) => b.cosine.compareTo(a.cosine));
      return FaceSearchResult(candidates, detected.length, stopwatch.elapsed);
    } finally {
      _busy = false;
    }
  }

  /// Extract raw camera faces once for a server-side gallery search. Uses the
  /// exact same alignment, models and feature pooling as searchImage.
  Future<FaceFrameSamples> extractImage(
    img.Image frame, {
    int maxFaces = 8,
  }) async {
    if (maxFaces < 1 || maxFaces > 8) throw ArgumentError.value(maxFaces);
    if (_busy) throw StateError('比对正在进行中');
    _busy = true;
    try {
      await initialize();
      final prepared = await compute(_prepareDecodedImage, frame);
      final detected = await _detectPrepared(prepared);
      final ranked = [...detected]
        ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
      final faces = <FaceSample>[];
      for (final detection in ranked) {
        if (faces.length >= maxFaces) break;
        try {
          faces.add(
            await _extractDetected(
              prepared,
              Uint8List(0),
              detection,
              detected.length,
            ),
          );
        } on FormatException {
          continue;
        }
      }
      return FaceFrameSamples(faces, detected.length);
    } finally {
      _busy = false;
    }
  }

  /// Release removed/replaced photo data immediately; retain only active inputs.
  void retainCachedPhotos(Iterable<Uint8List> photos) => _cache.retain(photos);

  Future<List<FaceSample>> _extractCachedFaces(
    Uint8List bytes,
    String label,
  ) async {
    final cached = _cache.lookup(bytes);
    if (cached != null) return cached;
    final _PreparedImage prepared;
    try {
      prepared = await compute(_prepareImage, bytes);
    } on FormatException catch (e) {
      throw FormatException('$label：${e.message}');
    }
    final result = await _extractPreparedFaces(prepared, bytes, label);
    _cache.put(bytes, result);
    return result;
  }

  Future<List<FaceSample>> _extractPreparedFaces(
    _PreparedImage prepared,
    Uint8List bytes,
    String label,
  ) async {
    try {
      final detected = await _detectPrepared(prepared);
      if (detected.isEmpty) {
        throw const FormatException('未检测到清晰人脸，请使用光线充足的正面照片');
      }
      // Stable largest-first order: confidence breaks area ties, detector order
      // breaks exact ties. Also provides deterministic tie-breaking for pairs.
      final ranked =
          detected.asMap().entries.toList()..sort((a, b) {
            final area = (b.value.width * b.value.height).compareTo(
              a.value.width * a.value.height,
            );
            if (area != 0) return area;
            final score = b.value.score.compareTo(a.value.score);
            return score != 0 ? score : a.key.compareTo(b.key);
          });
      // One owned preview shared by every face in this photo, never N file copies.
      final preview = Uint8List.fromList(bytes).asUnmodifiableView();
      final samples = <FaceSample>[];
      FormatException? lastFailure;
      for (final entry in compareAllFaces ? ranked : ranked.take(1)) {
        try {
          samples.add(
            await _extractDetected(
              prepared,
              preview,
              entry.value,
              detected.length,
            ),
          );
        } on FormatException catch (error) {
          if (!compareAllFaces) rethrow;
          lastFailure = error;
        }
      }
      if (samples.isEmpty) {
        throw FormatException(
          '没有可用于比对的人脸：${lastFailure?.message ?? '人脸过小或关键点无效'}',
        );
      }
      return List.unmodifiable(samples);
    } on FormatException catch (e) {
      throw FormatException('$label：${e.message}');
    }
  }

  Future<List<FaceDetection>> _detectPrepared(_PreparedImage prepared) async {
    final raw = await _infer(_detector!, prepared.tensor, [1, 3, 640, 640]);
    return decodeYuNet(raw).where((f) {
      final cx = f.x + f.width / 2, cy = f.y + f.height / 2;
      return cx >= 0 &&
          cy >= 0 &&
          cx < prepared.resizedWidth &&
          cy < prepared.resizedHeight;
    }).toList();
  }

  Future<FaceSample> _extractDetected(
    _PreparedImage prepared,
    Uint8List bytes,
    FaceDetection d,
    int faceCount,
  ) async {
    // Account for rounded resize dimensions separately when mapping to source.
    final sx = prepared.image.width / prepared.resizedWidth,
        sy = prepared.image.height / prepared.resizedHeight;
    var face = mapFaceDetection(d, scaleX: sx, scaleY: sy);
    if (math.min(face.width, face.height) < 60) {
      throw const FormatException('人脸太小，请使用人脸宽高至少 60 像素的照片');
    }
    // Small document portraits occupy few pixels in the whole-image pass.
    // Re-detect only the selected face using a crop from the original pixels.
    if (math.max(d.width, d.height) < 160) {
      final region = await compute(_prepareFaceRegion, (prepared.image, face));
      final refined = decodeYuNet(
        await _infer(_detector!, region.tensor, [1, 3, 640, 640]),
      ).map(
        (candidate) => mapFaceDetection(
          candidate,
          scaleX: region.width / region.resizedWidth,
          scaleY: region.height / region.resizedHeight,
          offsetX: region.x.toDouble(),
          offsetY: region.y.toDouble(),
        ),
      );
      // Do not jump to a nearby portrait or watermark in the document.
      final original = face;
      var bestOverlap = 0.5;
      for (final candidate in refined) {
        final overlap = intersectionOverUnion(original, candidate);
        if (overlap > bestOverlap) {
          face = candidate;
          bestOverlap = overlap;
        }
      }
    }
    final aligned = await compute(_alignFace, (prepared.image, face.landmarks));
    final features = await _infer(_recognizer!, aligned.tensor, [
      1,
      3,
      alignedFaceSize,
      alignedFaceSize,
    ]);
    var embedding = features.values.single;
    if (embedding.length != 256) {
      throw StateError('Unexpected Intel 0095 embedding size');
    }
    cosineSimilarity(
      embedding,
      embedding,
    ); // Reject zero or non-finite features.
    final auxiliary = aligned.auxiliaryTensor;
    if (auxiliary != null) {
      final extra = await _infer(_recognizer!, auxiliary, [1, 3, 128, 128]);
      embedding = poolDocumentFeatures(embedding, extra.values.single);
    }
    return FaceSample(
      preview: bytes.asUnmodifiableView(),
      alignedPreview: aligned.preview.asUnmodifiableView(),
      embedding: List.unmodifiable(embedding),
      detection: FaceDetection(
        x: face.x,
        y: face.y,
        width: face.width,
        height: face.height,
        score: face.score,
        landmarks: List.unmodifiable(face.landmarks),
      ),
      faceCount: faceCount,
      width: prepared.image.width,
      height: prepared.image.height,
    );
  }

  Future<void> close() async {
    // The owner must wait for compare/initialize before closing.
    if (_busy) throw StateError('Cannot close during comparison');
    _cache.clear();
    await _loading;
    await _detector?.close();
    await _recognizer?.close();
    _detector = null;
    _recognizer = null;
    _loading = null;
  }
}

class _PreparedImage {
  _PreparedImage(
    this.image,
    this.tensor,
    this.resizedWidth,
    this.resizedHeight,
  );
  final img.Image image;
  final Float32List tensor;
  final int resizedWidth, resizedHeight;
}

_PreparedImage _prepareImage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxFileBytes) {
    throw const FormatException('请选择 15 MB 以内的图片');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null) throw const FormatException('图片格式不支持，请使用 JPG、PNG 或 WebP');
  if (info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 24000000) {
    throw const FormatException('图片尺寸过大，请缩小至 2400 万像素以内');
  }
  var image = decoder!.decodeFrame(0);
  if (image == null) throw const FormatException('图片损坏或无法解码');
  image = img.bakeOrientation(image);
  // Retain full-resolution pixels for inference. The UI already decodes the
  // original bytes with cacheWidth; do not resize/JPEG-encode another preview.
  final (tensor, width, height) = _detectorInput(image);
  return _PreparedImage(image, tensor, width, height);
}

_PreparedImage _prepareDecodedImage(img.Image image) {
  if (image.width <= 0 ||
      image.height <= 0 ||
      image.width * image.height > 24000000) {
    throw const FormatException('相机画面尺寸无效');
  }
  final (tensor, width, height) = _detectorInput(image);
  return _PreparedImage(image, tensor, width, height);
}

(Float32List, int, int) _detectorInput(img.Image image) {
  final ratio = 640 / math.max(image.width, image.height);
  final width = math.max(1, (image.width * ratio).round()),
      height = math.max(1, (image.height * ratio).round());
  final tensor = resizedBgrTensor(image, width, height, 640);
  return (tensor, width, height);
}

class _FaceRegion {
  _FaceRegion(
    this.tensor,
    this.x,
    this.y,
    this.width,
    this.height,
    this.resizedWidth,
    this.resizedHeight,
  );
  final Float32List tensor;
  final int x, y, width, height, resizedWidth, resizedHeight;
}

_FaceRegion _prepareFaceRegion((img.Image, FaceDetection) input) {
  final (image, face) = input;
  final x = (face.x - face.width * 0.6).floor().clamp(0, image.width - 1);
  final y = (face.y - face.height * 0.6).floor().clamp(0, image.height - 1);
  final right = (face.x + face.width * 1.6).ceil().clamp(x + 1, image.width);
  final bottom = (face.y + face.height * 1.6).ceil().clamp(y + 1, image.height);
  final crop = img.copyCrop(
    image,
    x: x,
    y: y,
    width: right - x,
    height: bottom - y,
  );
  final (tensor, width, height) = _detectorInput(crop);
  return _FaceRegion(tensor, x, y, crop.width, crop.height, width, height);
}

class _AlignedFace {
  _AlignedFace(this.tensor, this.preview, this.auxiliaryTensor);
  final Float32List tensor;
  final Uint8List preview;
  final Float32List? auxiliaryTensor;
}

_AlignedFace _alignFace((img.Image, List<FacePoint>) input) {
  final (source, landmarks) = input;
  final transform = fitRecognitionAlignment(landmarks);
  final correction = fitDocumentCorrection(
    landmarks.map(transform.apply).toList(),
  );
  final (tensor, crop) = _sampleAligned(source, transform, null);
  final auxiliary = documentLuminanceTensor(
    correction == null
        ? tensor
        : _sampleAligned(source, transform, correction).$1,
  );
  return _AlignedFace(
    tensor,
    Uint8List.fromList(img.encodePng(crop)),
    auxiliary,
  );
}

(Float32List, img.Image) _sampleAligned(
  img.Image source,
  SimilarityTransform transform,
  DocumentCorrection? correction,
) {
  const size = alignedFaceSize;
  final crop = img.Image(width: size, height: size, numChannels: 3);
  final tensor = Float32List(3 * size * size);
  // Inverse warp with bilinear interpolation and a constant black border.
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final target = FacePoint(x.toDouble(), y.toDouble());
      final p = transform.inverse(correction?.inverse(target) ?? target);
      final x0 = p.x.floor(), y0 = p.y.floor(), fx = p.x - x0, fy = p.y - y0;
      final rgb = <double>[0, 0, 0];
      for (var dy = 0; dy <= 1; dy++) {
        for (var dx = 0; dx <= 1; dx++) {
          final px = x0 + dx, py = y0 + dy;
          if (px < 0 || py < 0 || px >= source.width || py >= source.height) {
            continue;
          }
          final q = source.getPixel(px, py),
              weight = (dx == 0 ? 1 - fx : fx) * (dy == 0 ? 1 - fy : fy);
          rgb[0] += q.r * weight;
          rgb[1] += q.g * weight;
          rgb[2] += q.b * weight;
        }
      }
      // Intel 0095 ONNX includes normalization. Feed raw BGR, not RGB.
      for (var c = 0; c < 3; c++) {
        tensor[c * size * size + y * size + x] = rgb[2 - c].roundToDouble();
      }
      crop.setPixelRgb(x, y, rgb[0].round(), rgb[1].round(), rgb[2].round());
    }
  }
  return (tensor, crop);
}
