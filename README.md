# eas_face

**On-device face comparison for Flutter Android and iOS.**

[pub.dev](https://pub.dev/packages/eas_face) · [English documentation](packages/eas_face/README.md) · [简体中文文档](packages/eas_face/README.zh-CN.md) · [Changelog](packages/eas_face/CHANGELOG.md)

Compare two photos locally and return similarity scores, face bounding boxes,
five landmarks, and aligned face thumbnails. YuNet detects faces and landmarks;
Intel 0095 extracts identity features. Both models are bundled with the SDK,
and inference runs on the device without a cloud recognition service.

## Features

- Compare the largest face in each photo by default, or opt into comparing all usable face pairs.
- Automatic color, lighting, and limited geometric assistance for document photographs.
- Original-image face boxes and five landmarks, plus coordinates in aligned thumbnails.
- Compact JSON output and an optional landmark overlay widget.
- Raw camera-frame comparison and ranked face search, with reusable model sessions and photo caching.

The displayed percentage is a model-derived score, not an identity probability.
Document-photo assistance is not a guarantee of accuracy; evaluate thresholds on
representative application data. The base `eas_face` package does not include liveness detection.

## Installation

```yaml
dependencies:
  eas_face: ^0.2.1
```

```sh
flutter pub get
```

Requires Flutter 3.29+, Dart 3.7+, Android API 24+, or iOS 16+.
The SDK supports Android and iOS; it does not provide a Web implementation.

## Quick start

```dart
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:eas_face/eas_face.dart';

Future<FaceComparison> comparePhotos(
  Uint8List referencePhoto,
  Uint8List comparisonPhoto,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = FaceEngine();
  try {
    await engine.initialize();
    return await engine.compare(referencePhoto, comparisonPhoto);
  } finally {
    await engine.close();
  }
}
```

For repeated comparisons, keep one engine, process requests serially, and close
it after pending work finishes. The host app handles photo selection, camera
permissions, and frame conversion.

## Documentation

| Guide | Contents |
| --- | --- |
| [English README](packages/eas_face/README.md) | Installation, API methods, parameters, result fields, and integration examples |
| [中文 README](packages/eas_face/README.zh-CN.md) | 中文接入说明、接口、参数与结果字段 |
| [JSON fields](packages/eas_face/JSON_FIELDS.md) | Exported scores, thresholds, boxes, and landmark coordinates |
| [Example app](packages/eas_face/example/README.md) | Minimal Android/iOS integration |
| [Agent guide](packages/eas_face/AGENT_GUIDE.md) | Detailed implementation and maintenance instructions |
| [Changelog](packages/eas_face/CHANGELOG.md) | Release history |

The SDK source lives in [`packages/eas_face/`](packages/eas_face/).
For a cloned repository, point a Flutter path dependency at that directory.

## Branches

| Branch | Purpose |
| --- | --- |
| [`main`](https://github.com/CrazyBoyKevin/eas-face/tree/main) | Default branch for the base SDK, without liveness detection |
| [`feat-eas-face`](https://github.com/CrazyBoyKevin/eas-face/tree/feat-eas-face) | Base SDK development branch |
| [`feat-eas-face-liveness`](https://github.com/CrazyBoyKevin/eas-face/tree/feat-eas-face-liveness) | Base SDK plus the experimental, unpublished liveness extension |

See the [liveness extension guide](https://github.com/CrazyBoyKevin/eas-face/blob/feat-eas-face-liveness/packages/eas_face_liveness/README.md)
for its current capabilities and known limitations.

## License

SDK code is licensed under [MIT](packages/eas_face/LICENSE).
Bundled models and dependencies retain their respective licenses; see
[third-party notices](packages/eas_face/THIRD_PARTY_NOTICES.md).
