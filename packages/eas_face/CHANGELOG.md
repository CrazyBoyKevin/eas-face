## 0.2.0

- 新增默认关闭的 `FaceEngine(compareAllFaces: true)`，compare / compareImage 比较两侧全部可用人脸组合，返回最高分组合；任意一组达标即通过。
- 偏色、光照与有限几何容错改为内部自动执行，移除 documentTolerance / documentColorTolerance 构造参数及属性；旧调用需删除这两个参数。
- 缓存扩展为每张照片的人脸集合，保留 JSON 结构，坐标与小图对应获选组合；增加多人、缓存、异常与原始帧回归测试。

- 新增 `searchImage` / `FaceSearchResult`，逐个比对多人画面中的可用人脸，按相似度排序，默认保留最大脸语义。

- 增加 `compareImage`，支持缓存参考照片与正向、非镜像原始相机图像串行比对，避免逐帧 JPEG 编解码。
- 相机结果的 `second.preview` 为空字节；对齐预览和 JSON 字段保持原有语义。

## 0.1.1

- Add optional geometric correction for mild document-photo distortion and default-on color/lighting assistance, processed entirely on device.
- Preserve face thumbnails, landmark coordinates, JSON fields and score thresholds; reuse bundled models and photo caching.
- Update integration documentation and regression tests. Color/lighting assistance remains experimental; recognition accuracy has not been evaluated.

## 0.1.0

Initial release of eas_face for Flutter Android and iOS.

- Fully on-device face comparison with bundled YuNet and Intel 0095 models.
- Largest-face selection, five-point alignment and original-resolution processing for small document portraits.
- Similarity percentage, configurable pass threshold, elapsed time and compact JSON results.
- Original-image face boxes and five landmarks, aligned face thumbnails and thumbnail landmark coordinates.
- Optional green/red landmark overlay, reusable model sessions and two-photo caching.
- Android/iOS example, integration guide, JSON field documentation and MIT license with third-party notices.
