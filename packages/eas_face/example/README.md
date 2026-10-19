# EAS Face SDK example

Minimal consumer for Android (API 24+) and iOS (16+).

```bash
flutter pub get
flutter devices
flutter run -d <device-id>
```

Select two local JPG/PNG/WebP photos and press Compare on device. Photos are processed locally. Model assets are supplied by the SDK; no host asset declarations are needed.

On iOS, choose your own signing team for device builds. The Android release template uses debug signing for demonstration only.

示例使用 `FaceEngine()`，现有偏色、光照与有限几何容错由 SDK 自动执行。需要多人任意匹配时改用 `FaceEngine(compareAllFaces: true)`；compare 返回最高分组合，`matches(0.60)` 表示至少一组达标。严重弯曲、折痕或反光遮挡仍无法可靠修复。
