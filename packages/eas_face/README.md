# eas_face

English | [简体中文](README.zh-CN.md)

**On-device face comparison for Flutter Android and iOS.**

Compare two photos and obtain a similarity score, face bounding boxes, five
landmarks, and aligned face thumbnails. YuNet and Intel 0095 models are bundled;
images are processed on the device without a cloud recognition service.

By default, the largest face in each photo is compared. An optional mode compares
all usable face pairs and returns the pair with the highest score.
**This package does not include liveness detection.**

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Multiple faces](#multiple-faces)
- [Document-photo assistance and migration](#document-photo-assistance-and-migration)
- [Engine methods](#engine-methods)
- [Comparison results](#comparison-results)
- [Face data and coordinates](#face-data-and-coordinates)
- [JSON output](#json-output)
- [Camera frames and face search](#camera-frames-and-face-search)
- [Landmark overlay](#landmark-overlay)
- [Errors and lifecycle](#errors-and-lifecycle)
- [Validation and licenses](#validation-and-licenses)

## Requirements

| Requirement | Supported value |
| --- | --- |
| Flutter | 3.29.0 or later |
| Dart | >=3.7.0 and <4.0.0 |
| Android | API 24 or later |
| iOS | 16.0 or later |
| Encoded image formats | JPEG, PNG, WebP |
| Maximum encoded image size | 15 MiB and 24 million pixels per image |

This SDK supports mobile apps only. Convert HEIC locally before passing it to the
SDK. The host application handles camera access, image selection, and permissions.

## Installation

```yaml
dependencies:
  eas_face: ^0.2.0
```

```sh
flutter pub get
```

For a source checkout, use the SDK directory as a path dependency:

```yaml
dependencies:
  eas_face:
    path: ../eas_face
```

The package declares its own model assets. Do not declare them again in the host
app. The two models total approximately **4.48 MiB**; the native inference runtime
adds separate overhead.

## Quick start

```dart
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:eas_face/eas_face.dart';

Future<FaceComparison> comparePhotos(Uint8List first, Uint8List second) async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = FaceEngine();
  try {
    await engine.initialize();
    return await engine.compare(first, second);
  } finally {
    await engine.close();
  }
}
```

For repeated comparisons, keep one `FaceEngine` for the screen or service, load it
once, perform calls **serially**, and close it when work has finished. The engine
reuses model sessions and caches results for up to two photos.

## Multiple faces

```dart
final engine = FaceEngine(compareAllFaces: true);
await engine.initialize();
final result = await engine.compare(photoABytes, photoBBytes);
final passed = result.matches(0.60);
// Close the engine after all pending operations finish.
```

| Constructor parameter / property | Type | Default | Behavior |
| --- | --- | --- | --- |
| `compareAllFaces` | `bool` | `false` | Controls face selection for `compare` and `compareImage`; read-only after construction. |

- With the default setting, each photo's largest detected face is selected.
- With the option enabled, N usable faces in one photo and M in the other produce
  N x M comparisons. Processing does not stop at the first passing pair.
- The highest-scoring pair is returned, even if no pair passes the threshold.
  Both `FaceSample` values, thumbnails, landmarks, and JSON coordinates refer to
  that winning pair. Ties are resolved deterministically using face ordering.
- Features are extracted once per usable face. More faces increase processing
  time and memory use; this mode does not silently truncate the face list.
- Faces smaller than 60 pixels on either source-image dimension, or faces that
  cannot be aligned, are skipped in all-face mode. `faceCount` still reports the
  total detected count. No usable face on either side causes a `FormatException`.
- Create a new engine to change modes. Set the passing threshold using `matches`
  or the JSON methods; it is independent of face selection.

## Document-photo assistance and migration

Color, lighting, and limited geometric assistance run automatically. The SDK
extracts a standard view and an auxiliary view and pools their features with
fixed weights. It does not choose a preprocessing method based on whichever
produces a higher comparison score.

Original images, standard aligned thumbnails, public coordinates, and JSON field
names retain their existing meanings. No additional model download is needed.
When distortion exceeds the geometric correction limits, that correction is
skipped while the color/lighting assistance remains enabled.

This cannot reliably restore details lost to severe folds, glare, blur, or large
viewing angles. It does not guarantee higher scores, and color assistance has not
been validated for accuracy on a representative business dataset.

**Migrating from 0.1.1:** remove `documentTolerance` and
`documentColorTolerance` constructor arguments and property accesses. Use
`FaceEngine()` directly. Regenerate persisted embeddings produced by older
preprocessing pipelines; do not mix them with newly extracted embeddings.
Multi-face comparison remains opt-in through `compareAllFaces: true`.

## Engine methods

| Method | Returns | Purpose |
| --- | --- | --- |
| `initialize()` | `Future<void>` | Preload models before the first comparison. |
| `compare(first, second, onProgress: callback)` | `Future<FaceComparison>` | Compare two encoded image byte arrays. |
| `compareImage(reference, frame)` | `Future<FaceComparison>` | Compare encoded reference bytes against a decoded camera image. |
| `searchImage(reference, frame)` | `Future<FaceSearchResult>` | Rank every usable camera face against one reference face. |
| `extractImage(frame, maxFaces: 8)` | `Future<FaceFrameSamples>` | Extract up to 1-8 usable faces without a reference comparison. |
| `retainCachedPhotos(activePhotos)` | `void` | Retain only the listed encoded photos in the cache; `[]` clears it. |
| `close()` | `Future<void>` | Release sessions and cached data after pending work completes. |

`isReady` is a read-only `bool`. The optional progress callback has type
`void Function(String)?`; it reports stages, not a completion percentage.

## Comparison results

`compare` and `compareImage` return a `FaceComparison`.

| Property | Type | Meaning |
| --- | --- | --- |
| `likeness` | `double` | Display score in the range 0-1. |
| `cosine` | `double` | Raw cosine similarity, available for evaluation. |
| `elapsed` | `Duration` | Processing time; may include initial model loading. |
| `first` | `FaceSample` | Selected face from the first/reference image. |
| `second` | `FaceSample` | Selected face from the second/camera image. |

| Function / method | Purpose |
| --- | --- |
| `formatLikeness(result.likeness)` | Format the display score, for example `75.20%`. |
| `result.matches(0.60)` | Apply a required threshold on the 0-1 display scale. |
| `result.elapsed.inMicroseconds / 1000` | Obtain processing time in milliseconds. |

Pass **`0.60`, not `60`**, for a 60% threshold. The displayed percentage is a
mapping of the model score, not a measured proportion of visual resemblance or a
probability that two people have the same identity. Decisions use the unrounded
score. Calibrate thresholds on representative matching and non-matching pairs.

## Face data and coordinates

For example, `final face = result.first;`.

### Source-image data

| Property | Type | Meaning |
| --- | --- | --- |
| `preview` | `Uint8List` | Original encoded file bytes; empty for camera-frame samples. |
| `width`, `height` | `int` | Source image dimensions after orientation correction. |
| `faceCount` | `int` | Total number of faces detected in the image. |
| `detection.x`, `detection.y` | `double` | Selected bounding box's top-left position. |
| `detection.width`, `detection.height` | `double` | Bounding box dimensions in source pixels. |
| `detection.score` | `double` | Face detector confidence. |
| `detection.landmarks` | `List<FacePoint>` | Five landmarks in source-image pixels. |
| `embedding` | `List<double>` | Recognition feature vector; omitted from JSON output. |

### Aligned thumbnail

| Property | Type | Meaning |
| --- | --- | --- |
| `alignedPreview` | `Uint8List` | Encoded PNG thumbnail. |
| `alignedWidth`, `alignedHeight` | `int` | Thumbnail dimensions; currently 128 x 128. |
| `alignedLandmarks` | `List<FacePoint>` | Detected landmarks mapped into thumbnail pixels. |

Each `FacePoint` has `double x` and `double y`. Both coordinate systems use the
top-left origin, with x increasing rightward and y increasing downward.

| Index | Landmark, as seen in the image |
| --- | --- |
| 0 | Image-left eye |
| 1 | Image-right eye |
| 2 | Nose |
| 3 | Image-left mouth corner |
| 4 | Image-right mouth corner |

Use source landmarks with the source image and aligned landmarks with the
thumbnail. Source coordinates refer to the EXIF-oriented image; display the
original file with its orientation applied. Dart coordinates retain fractional
values; JSON coordinates are rounded to integers.

## JSON output

| Method | Return type | Use |
| --- | --- | --- |
| `result.toJson(threshold: 0.60)` | `Map<String, Object>` | Structured data for the caller. |
| `result.toJsonString(threshold: 0.60)` | `String` | Copyable, formatted JSON. |

Both methods default to `threshold: 0.60`.

| JSON field | Meaning |
| --- | --- |
| `likenessPercent` | Display percentage from 0.00 to 100.00. |
| `thresholdPercent` | Passing threshold as a percentage. |
| `passed` | Whether the unrounded display score meets the threshold. |
| `elapsedMs` | Processing time in milliseconds. |
| `first.faceBox`, `second.faceBox` | Source-image `x`, `y`, `width`, and `height`, all integers. |
| `first.landmarks`, `second.landmarks` | Five objects containing `name`, integer `x`, and integer `y`. |

Landmark names are `imageLeftEye`, `imageRightEye`, `nose`, `imageLeftMouth`, and
`imageRightMouth`. Formatted JSON uses two decimal places for percentages and time.
It includes no image bytes, embeddings, or aligned-thumbnail coordinates.
See [JSON_FIELDS.md](JSON_FIELDS.md) for the detailed Chinese field reference.

## Camera frames and face search

Add `image` as a direct dependency if your application uses its types. Supply an
upright, unmirrored `package:image` `Image`; camera format conversion, permissions,
and capture lifecycle are the host application's responsibility.

`compareImage(referenceBytes, frame)` uses the same recognition and scoring
pipeline as `compare`. It caches the reference photo, but does not JPEG-encode or
cache the live frame. `second.preview` is empty; its aligned thumbnail, bounding
box, landmarks, and embedding remain available.

`searchImage(referenceBytes, frame)` is an explicit search API independent of
`compareAllFaces`. It uses one reference face and returns all usable frame faces.
Use a single-person reference photo. An empty frame returns no candidates;
inference failures propagate as errors.

| `FaceSearchResult` property / method | Meaning |
| --- | --- |
| `candidates` | `List<FaceComparison>`, sorted by descending raw cosine score. |
| `best` | First candidate, or `null`; being the best does not imply a match. |
| `matches(threshold)` | All candidates meeting the display-score threshold. |
| `detectedFaceCount` | Total faces detected in the frame. |
| `skippedFaceCount` | Detected faces skipped because no usable sample was extracted. |
| `elapsed` | Time to process the complete frame. |

Full-frame detection is shared; small faces may be re-detected locally for
refinement. Processing time increases with candidate count. The SDK does not
resolve identity ambiguity or certify liveness; the application decides how to
handle multiple matching candidates and how to confirm a match across frames.

`extractImage` returns `FaceFrameSamples.faces` and `detectedFaceCount`, without
performing identity comparison. This SDK itself performs no network requests.

## Landmark overlay

```dart
import 'package:flutter/material.dart';
import 'package:eas_face/eas_face.dart';
import 'package:eas_face/eas_face_widgets.dart';

Widget faceThumbnail(FaceSample face, bool passed) => SizedBox(
  width: 160,
  height: 160,
  child: Stack(fit: StackFit.expand, children: [
    Image.memory(face.alignedPreview, fit: BoxFit.contain),
    FaceLandmarkOverlay(
      imageSize: Size(
        face.alignedWidth.toDouble(),
        face.alignedHeight.toDouble(),
      ),
      points: face.alignedLandmarks,
      matches: passed,
    ),
  ]),
);
```

Use `faceThumbnail(result.first, result.matches(0.60))`. The overlay positions
points with centered `BoxFit.contain`. Points are green for a passing comparison
and red otherwise, with no numeric labels.

## Errors and lifecycle

| Exception | Typical cause | Handling |
| --- | --- | --- |
| `FormatException` | Invalid or oversized image, no face, face too small, or invalid alignment. | Check input; a usable source face must be at least 60 pixels wide and high. |
| `UnsupportedError` | Initialization on an unsupported platform. | Use Android or iOS. |
| `StateError` | Concurrent calls, closing during inference, or invalid runtime state. | Serialize calls and inspect the error. |
| Other exceptions | Asset loading or native runtime failure. | Handle separately from a non-matching result. |

Preload once, reuse the engine, and wait for pending inference before closing it.
An error is not a failed identity comparison; do not replace errors with an
invented low score.

## Validation and licenses

A minimal mobile app is included in [example/](example/README.md):

```sh
cd example
flutter pub get
flutter run -d <device-id>
```

The 0.2.0 release passed static analysis and 42 SDK tests. These checks cover
geometry, score handling, caching, multi-face selection, and failure paths;
they do not establish business accuracy or real-device latency. Severe glare,
blur, large angles, and damaged document portraits can still reduce reliability.

SDK code is [MIT licensed](LICENSE). Model and dependency terms are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

See [CHANGELOG.md](CHANGELOG.md) for release notes and
[AGENT_GUIDE.md](AGENT_GUIDE.md) for the detailed maintainer guide in Chinese.
