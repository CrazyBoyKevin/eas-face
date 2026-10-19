# eas_face

**Flutter 本地人脸比对 SDK · Android / iOS · 0.2.0（本地未发布）**

传入两张照片，获取相似分数、人脸框、五个关键点和对齐后的人脸小图。模型随包提供，照片在设备上处理，无需云端识别服务。多人照片默认选取面积最大的人脸，可通过参数开启所有可用人脸组合比对。

## 阅读导航

| 你想做什么 | 阅读位置 |
| --- | --- |
| 安装并完成第一次比对 | [快速开始](#快速开始) |
| 开启多人任意匹配 | [多人比对](#多人比对) |
| 优化轻度变形的证件翻拍 | [证件翻拍容错](#证件翻拍容错) |
| 查看分数、通过结果和耗时 | [读取比对结果](#读取比对结果) |
| 获取框、五点或人脸小图 | [读取人脸数据](#读取人脸数据) |
| 导出 JSON 给调用方 | [导出 JSON](#导出-json) |
| 在图片上画绿色/红色点位 | [展示人脸小图与点位](#展示人脸小图与点位) |
| 管理缓存、释放资源或处理失败 | [生命周期与异常](#生命周期与异常) |
| 查完整接口或让 AI Agent 维护代码 | [AI Agent 技术指南](AGENT_GUIDE.md) |

## 快速开始

### 1. 确认环境

| 项目 | 要求 |
| --- | --- |
| Flutter | 3.29.0 或以上 |
| Dart | 3.7.0 或以上，低于 4.0.0 |
| Android | API 24 或以上 |
| iOS | 16.0 或以上 |
| 图片 | JPG / PNG / WebP；单张不超过 15 MiB、2400 万像素 |

SDK 仅支持 App 端。HEIC 请先在本地转为支持的格式。拍照、选图和权限由宿主 App 处理，SDK 不包含选择器。

### 2. 添加依赖

pub.dev 当前已发布版为 0.1.1；以下依赖用于已发布版本：

```yaml
dependencies:
  eas_face: ^0.1.1
```

然后执行：

```bash
flutter pub get
```

本次 0.2.0 新接口尚未发布，请使用源码或本地 SDK 依赖，将路径替换为你的实际目录：

```yaml
dependencies:
  eas_face:
    path: ../eas_face
```

包内已包含离线模型，无需在宿主重复声明模型 assets。模型合计约 4.48 MiB，原生运行库另占体积。

### 3. 完成一次比对

下面的函数展示完整的一次性调用，可传入选图工具读取的两份文件字节：

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

需要连续比对时，在页面或服务中**复用一个 `FaceEngine`**，初始化一次，多次串行调用 `compare`，最后再关闭。这样可复用模型和最近两张照片的处理结果。

## 多人比对

```dart
// 默认：两张照片各选最大脸。
final engine = FaceEngine();

// 可选：比较两张照片中的全部可用人脸组合。
final multiEngine = FaceEngine(compareAllFaces: true);
await multiEngine.initialize();
final result = await multiEngine.compare(photoABytes, photoBBytes);
final passed = result.matches(0.60); // 任意一组达标即通过。
```

| 参数 / 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `compareAllFaces` | `bool` | `false` | 构造参数及只读属性；控制 `compare`、`compareImage` 是否遍历两侧全部可用人脸。 |

- 一侧单人、另一侧多人，或者两侧都多人，均支持。两侧分别有 N、M 张可用人脸时，计算 N×M 个组合；不在首次达标时提前结束。
- 返回最高分那一组的 `FaceComparison`。`first`、`second`、小图、五点及 JSON 坐标均对应这一组；全部未达标时仍返回最高分，但 `matches(threshold)` 为 false。分数完全相同时按面积、检测置信度和检测顺序稳定选择。
- 每张脸只提取一次特征，照片缓存仍最多两张。人越多，耗时和内存使用越高；不会为加速而只选前几张脸。
- 小于原图 60 像素或不能对齐的人脸跳过，`faceCount` 仍是检测总数。某侧没有可用人脸时抛 `FormatException`；运行时错误向上传播，不当成不匹配。
- 阈值仍由 `matches` / `toJson` 的 threshold 决定。切换多人模式需创建新引擎，缓存不会混用。

## 自动翻拍容错

偏色、光照与有限几何校正作为 SDK 内部流程自动开启，调用方无需配置。每张脸生成标准视图和辅助视图，固定融合两份特征；不根据分数挑选预处理方案，也不改变分数映射或通过线。原图、标准对齐小图、公开坐标及 JSON 结构保持不变。

无需下载新模型，仍全部在设备本地运行。几何校正超出限制时仅跳过几何修正，偏色/光照辅助继续执行。不能保证所有输入得分提高；严重弯曲、折痕、强反光遮挡和丢失的细节尚不能可靠恢复。偏色辅助仍缺少业务准确率评测。

**从 0.1.1 迁移：** 删除构造参数 `documentTolerance`、`documentColorTolerance` 及相应属性访问，直接使用 `FaceEngine()`。旧版本提取的持久化特征应重新生成，不要混合新旧处理流程。新增多人模式只有显式传入 `compareAllFaces: true` 才启用。

## 读取比对结果

`compare` 返回 `FaceComparison`。常用字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `likeness` | `double` | 0～1 的显示分数。 |
| `elapsed` | `Duration` | 本次总耗时，可能包含首次模型初始化。 |
| `first` | `FaceSample` | 第一张照片的人脸数据。 |
| `second` | `FaceSample` | 第二张照片的人脸数据。 |
| `cosine` | `double` | 原始余弦分数，供评测使用。 |

格式化与判断是方法调用，和上面的字段分开使用：

```dart
final result = await engine.compare(photoABytes, photoBBytes);
final percentage = formatLikeness(result.likeness); // 例如 75.20%
final passed = result.matches(0.60);                // 60% 通过线
final milliseconds = result.elapsed.inMicroseconds / 1000;
```

`matches` 必须传入阈值，`0.60` 表示 60%，不要传 `60`。百分比是模型分数的显示换算，不是身份概率或真实相像比例；通过判断使用未舍入的分数。具体换算见 [技术指南](AGENT_GUIDE.md#61-分数换算)。

## 读取人脸数据

先选一侧，例如 `final face = result.first;`。

### 原图与人脸框

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `face.preview` | `Uint8List` | 原始照片文件字节。 |
| `face.width` | `int` | 方向校正后的原图宽度，像素。 |
| `face.height` | `int` | 方向校正后的原图高度，像素。 |
| `face.faceCount` | `int` | 全图检测到的人脸数量。 |
| `face.detection.x` | `double` | 选中人脸框左上角 x。 |
| `face.detection.y` | `double` | 选中人脸框左上角 y。 |
| `face.detection.width` | `double` | 人脸框宽度。 |
| `face.detection.height` | `double` | 人脸框高度。 |
| `face.detection.landmarks` | `List<FacePoint>` | 原图中的五点坐标。 |

### 对齐后的人脸小图

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `face.alignedPreview` | `Uint8List` | PNG 小图字节。 |
| `face.alignedWidth` | `int` | 小图宽度，当前为 128 像素。 |
| `face.alignedHeight` | `int` | 小图高度，当前为 128 像素。 |
| `face.alignedLandmarks` | `List<FacePoint>` | 小图中的五点坐标。 |

每个 `FacePoint` 分别包含 `double x` 和 `double y`。两种坐标都以图片左上角为原点，x 向右、y 向下；五点顺序固定为：

| 下标 | 点位 |
| --- | --- |
| 0 | 图像左眼 |
| 1 | 图像右眼 |
| 2 | 鼻尖 |
| 3 | 图像左嘴角 |
| 4 | 图像右嘴角 |

**原图点位配原图，小图点位配小图。** 原图坐标基于 EXIF 方向校正后的图像，显示原始文件时也需正确处理方向。Dart 坐标保留小数，JSON 导出取整。

## 导出 JSON

| 方法 | 返回值 | 用途 |
| --- | --- | --- |
| `result.toJson(threshold: 0.60)` | `Map<String, Object>` | 交给调用方继续处理。 |
| `result.toJsonString(threshold: 0.60)` | `String` | 直接复制或展示 JSON 文本。 |

两种方法的 `threshold` 都可省略，默认 `0.60`。

| 顶层字段 | 含义 |
| --- | --- |
| `likenessPercent` | 相似百分比，0.00～100.00。 |
| `thresholdPercent` | 通过标准，例如 60.00。 |
| `passed` | 是否通过。 |
| `elapsedMs` | 耗时，毫秒。 |
| `first` | 第一张照片的 `faceBox` 和 `landmarks`。 |
| `second` | 第二张照片的 `faceBox` 和 `landmarks`。 |

JSON 文本的百分比和耗时保留两位小数，框与点位为原图整数坐标；不包含照片、特征向量或小图坐标。完整字段解释见 [JSON_FIELDS.md](JSON_FIELDS.md)。

## 展示人脸小图与点位

下面的组件显示对齐小图，并根据比对结果绘制五个点：通过为绿色，不通过为红色。

```dart
import 'package:flutter/material.dart';
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

调用时使用 `faceThumbnail(result.first, result.matches(0.60))`。覆盖层按居中 `BoxFit.contain` 定位，不绘制坐标数字。

## 生命周期与异常

### 引擎方法速查

| 方法 | 使用时机 |
| --- | --- |
| `await engine.initialize()` | 页面准备阶段预加载模型，减少首次比对等待。 |
| `await engine.compare(a, b, onProgress: callback)` | 串行执行比对；可选回调接收阶段文字。 |
| `engine.retainCachedPhotos(activePhotos)` | 保留仍在使用的照片缓存，传 `[]` 清空。 |
| `await engine.close()` | 当前操作结束后释放模型与缓存。 |

`engine.isReady` 是只读布尔属性，用来判断模型是否加载完成。

`onProgress` 的类型为 `void Function(String)?`，它提供阶段提示，不提供完成百分比。同一引擎不允许并发比对，也不能在比对中关闭。

### 错误处理

| 异常 | 常见原因 | 建议 |
| --- | --- | --- |
| `FormatException` | 文件无效、尺寸超限、无脸或脸太小。 | 提示用户检查输入；原图人脸宽高至少 60 像素。 |
| `UnsupportedError` | 在不支持的平台初始化。 | 使用 Android/iOS。 |
| `StateError` | 并发调用、比对中关闭或运行时状态错误。 | 检查调用顺序与错误信息。 |
| 其他异常 | 模型加载或原生推理失败。 | 捕获错误并记录必要诊断信息。 |

失败不等于“不通过”；应单独展示错误，而不是生成一个低分结果。

## 示例、验证与许可

最小 App 示例位于 [example/](example/README.md)：

```bash
cd example
flutter pub get
flutter run -d <设备ID>
```

当前实现新增多人组合与缓存回归测试，验证范围见技术指南。此前几何模式完成 16 组合成变体的本地 WASM 回归，包含不同人对照；这些结果不验证新增偏色模式的识别效果。模型实现曾完成 Android/iOS 构建，改名后尚未重新做原生构建；尚未完成真机性能和大规模业务准确率验证。护照反光、严重模糊或大角度仍可能影响结果，SDK 不包含活体检测。

SDK 代码使用 [MIT 许可证](LICENSE)，模型与依赖许可见 [第三方声明](THIRD_PARTY_NOTICES.md)。

维护、完整 API、模型处理和验证步骤见 [AGENT_GUIDE.md](AGENT_GUIDE.md)；版本摘要见 [CHANGELOG.md](CHANGELOG.md)。


## 多人画面查找

`await engine.searchImage(referenceBytes, uprightUnmirroredImage)` 返回 `FaceSearchResult`：

- `candidates`：所有可提取特征的人脸，按原始余弦相似度降序排列，每项是 `FaceComparison`。
- `best`：第一候选或 null；最高分不等于匹配，仍需检查阈值。
- `matches(threshold)`：所有达标候选。Demo 仅在唯一候选达标且连续三帧确认后标绿；多个达标提示无法唯一确认。
- `detectedFaceCount` / `skippedFaceCount`：检测数 / 因尺寸不足或对齐无效跳过的数量。
- `elapsed`：整帧全部人脸处理耗时。候选越多，处理耗时越长。

全图只检测一次，各脸复用原有对齐和特征流水线；小脸按原有逻辑局部复检。没有人脸时返回空列表。模型运行异常向上传播。`searchImage` 是独立搜索接口，不受 `compareAllFaces` 控制；参考照片使用最大可用人脸，建议单人照。`compare` 和 `compareImage` 则按引擎的 `compareAllFaces` 选择最大脸或全部组合。相机帧的 preview 为空，使用实时预览和检测框展示。

## 相机原始帧接入（工作区新增 API）

`await engine.compareImage(referenceBytes, image)` 接受参考照片文件字节和 `package:image` 的 `Image`。调用方负责将相机帧转为正向、非镜像像素。参考照片使用已有缓存，实时帧不编码为 JPEG、不加入照片缓存；检测、对齐、辅助特征和阈值与 `compare` 相同。调用必须串行，关闭前等待推理完成。

返回 `FaceComparison`；实时帧的 `second.preview` 是空字节（使用相机预览），`second.alignedPreview`、检测框、关键点和特征仍有效。原有 `compare` 的预览与 JSON 契约不变。SDK 仍不负责相机权限、帧格式或生命周期。
