# eas_face_liveness

为 `eas_face` 增加**设备本地、双模型静默活体检测**的 Flutter 扩展包。
支持 Android API 24+ / iOS 16+。使用 MiniFASNetV2 + MiniFASNetV1SE，不上传图片，不调用云端接口。

当前为 **0.1.1 本地开发版，尚未发布**。本包依赖当前工作区的 `eas_face 0.2.0`；
使用 `searchImage` 复用人脸检测与参考照片缓存，不能直接替换为缺少该接口的旧发布版。

## 已知问题与当前改进

2026-10-16 真机测试中，用户报告旧版单模型会接受另一块屏幕上的放大静态照片；旧版不能作为可靠活体门槛。0.1.1 加入第二个模型，两者分别使用 2.7× / 4× 周边裁剪，`liveScore` 取两个活体分数的较小值，阈值仍为 0.90，不用平均值抵消某个模型的拒绝。`modelScores` 返回两路原始分数，供复测诊断。

联合验证及 demo 在原图无法提供至少 2.7× 人脸周边时返回 `insufficientContext`，提示后退。这个限制只是输入质量约束，**不是屏幕检测**；4× 裁剪仍按上游规则受原图边界限制。低层 `evaluateFrame` 保留上游边界裁剪行为，调用方须单独检查 `availableLivenessContext`。

这版是候选改进，尚未证明能拦截上述攻击。需重新测试真人、不同大小/亮度/距离的屏幕照片与打印照片，记录误接受及误拒绝。若屏幕样例仍通过，不能继续靠增加连续帧数或提高单一阈值宣称修复。

## 包的关系

| 包 | 职责 | 模型 |
|---|---|---|
| `eas_face` | 人脸检测、五点定位、身份比对 | YuNet + Intel 0095 |
| `eas_face_liveness` | 活体推理、多帧确认、身份与活体联合验证 | MiniFASNetV2（2.7×）+ MiniFASNetV1SE（4×） |

两个包共用 `flutter_onnxruntime 1.9.0`，不增加第二套推理引擎。
原 `eas_face` 无需依赖本包；仅使用原包时不会引入活体模型。
本包新增 ONNX 文件 共 **3,486,238 字节（3.49 MB / 3.32 MiB）**。
这是模型资源大小，不是最终 APK/IPA 的安装体积增量。

## 本地接入

保持两个包为相邻目录：

```text
packages/
  eas_face/
  eas_face_liveness/
```

应用 `pubspec.yaml`：

```yaml
dependencies:
  eas_face_liveness:
    path: packages/eas_face_liveness
  image: ^4.5.4
```

相机权限、相机插件和图像方向转换由应用负责。本包只接收 `image` 包的 `Image`。

## 推荐接口：联合验证

```dart
import 'dart:typed_data';
import 'package:eas_face_liveness/eas_face_liveness.dart';
import 'package:image/image.dart' as img;

final verifier = LiveFaceVerifier();
await verifier.initialize(); // 在开始采集前预热

// 每次传入一张新的相机帧。不要并发调用，忙时丢弃积压帧。
Future<bool> processFrame(Uint8List passportPhoto, img.Image cameraFrame) async {
  final result = await verifier.verifyFrame(passportPhoto, cameraFrame);
  print(result.toJson());
  return result.passed; // 同一张现场人脸同时通过身份比对与连续活体确认
}

// 暂停、切换相机、切换参考对象或退出页面时立即调用。
verifier.reset();
// 等当前 verifyFrame 完成后释放资源。
await verifier.close();
```

- 参考护照照片只参与身份比对，**不做活体检测**。
- `cameraFrame` 必须是当前相机的新帧，方向正确且未镜像；不要传入人脸小图、截图、翻拍证件或经过偏色校正的图像。
- 此首版联合接口要求参考照片及相机画面各一张人脸；多人入镜时重置确认，不选择其中一人直接通过。
- 原 `eas_face` 的可选多人比对接口保持原有行为。
- 相机暂停后请清除 UI 旧通过状态。返回对象是一帧的快照，不是持续有效的凭证。
- 如果传入自定义引擎，验证器会接管其生命周期；不要同时在其他流程使用或关闭它们。

### `LiveFaceVerifier` 参数

| 参数 | 默认值 | 含义 |
|---|---|---|
| `faceEngine` | 新建 `FaceEngine()` | 身份比对引擎，可复用现有实例；不支持并发共用 |
| `livenessEngine` | 新建 `FaceLivenessEngine()` | 活体推理引擎 |
| `session` | 新建 `PassiveLivenessSession()` | 连续帧确认策略 |
| `matchThreshold` | `0.60` | 身份相像度通过线，与活体阈值独立 |

### 方法

| 方法 | 返回值 | 作用 |
|---|---|---|
| `initialize()` | `Future<void>` | 加载四个本地模型（检测、识别、两个活体），建议提前调用 |
| `verifyFrame(reference, frame)` | `Future<LiveFaceVerification>` | 处理一帧并更新连续确认 |
| `reset()` | `void` | 清除累积状态，并使处理中帧失效 |
| `close()` | `Future<void>` | 释放两个引擎；关闭后不可复用 |

### 联合结果字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `passed` | `bool` | 当前帧是否同时满足身份比对和连续活体要求 |
| `status` | `LiveVerificationStatus` | 当前状态，见下表 |
| `search` | `FaceSearchResult` | 原 SDK 比对结果；独立通过身份比对不代表活体通过 |
| `liveness` | `LivenessFrameResult?` | 当前脸的活体分数及耗时；未推理时为 `null` |
| `decision` | `LivenessDecision?` | 连续确认状态、已接纳帧数和观察时长 |
| `elapsed` | `Duration` | 当前帧完整处理时间，含身份比对与活体；不含应用取帧与转换 |

### 状态值

| 状态 | 说明 | `passed` |
|---|---|---|
| `noFace` | 未检测到现场人脸 | `false` |
| `multipleFaces` | 参考照片或现场画面有多张人脸 | `false` |
| `unusableFace` | 检测到了人脸但无法提取可用特征 | `false` |
| `insufficientContext` | 人脸过近，原图不足以提供至少 2.7× 周边区域 | `false` |
| `identityMismatch` | 身份比对未通过 | `false` |
| `collecting` | 正在积累活体证据，或处理期间被重置 | `false` |
| `spoofSuspected` | 当前帧活体分数不足 | `false` |
| `live` | 当前身份与活体联合通过 | `true` |

图像不符合要求或运行时失败会抛出异常，并清空连续确认。调用方应清除旧通过状态，不能把异常当作成功。

## JSON 字段

`result.toJson()` 可交给 `jsonEncode`。数值按两位小数舍入，坐标为整数；JSON 数字不会强制保留末尾零。

| 字段 | 类型 | 说明 |
|---|---|---|
| `passed` | boolean | 联合结果 |
| `status` | string | 上表状态名称 |
| `elapsedMs` | number | 当前帧完整 SDK 处理时间 |
| `observationMs` | number | 当前连续确认段的时间跨度 |
| `acceptedFrames` | integer | 当前确认段接纳的帧数 |
| `comparison` | object/null | 原比对 JSON：相似度、阈值、身份比对结论、双方人脸框与五点 |
| `liveness` | object/null | 以下活体单帧数据 |
| `liveness.liveScore` | number | 两模型活体分数的最小值，未经业务概率校准 |
| `liveness.modelScores` | object | `texture2_7` 与 `context4` 两路分数 |
| `liveness.preprocessMs` | number | 活体裁剪、缩放和张量准备耗时 |
| `liveness.inferenceMs` | number | 张量创建、原生推理、结果读取与分数计算耗时 |
| `liveness.elapsedMs` | number | 单帧活体处理耗时；首次调用可能包含模型加载 |
| `liveness.faceBox` | object | 原始现场图像内 `x`、`y`、`width`、`height`，左上角原点，像素整数 |

业务最终结论请读取顶层 `passed`，不要单独使用 `comparison.passed`。

## 自定义连续确认

```dart
final verifier = LiveFaceVerifier(
  session: PassiveLivenessSession(
    threshold: 0.90,
    minimumFrames: 3,
    minimumObservation: const Duration(milliseconds: 600),
    minimumInterval: const Duration(milliseconds: 100),
    maximumGap: const Duration(milliseconds: 700),
  ),
);
```

| 参数 | 作用 |
|---|---|
| `threshold` | 每个接纳帧的活体分数下限；默认 0.90 是初始工程值，未经业务样本标定 |
| `minimumFrames` | 至少接纳的帧数，最小 2 |
| `minimumObservation` | 连续观察的最小时长，必须大于零 |
| `minimumInterval` | 计数帧之间的最短间隔，防止高帧率使计数过早达标 |
| `maximumGap` | 两帧间超过该间隔则重置；必须大于最短间隔 |

默认要求至少 3 帧且跨度不少于 600 ms。低分、追踪框明显跳变、时间倒退、缺失或中断都会清除确认。
帧间 IoU 只是连续性约束，联合接口还要求每一帧匹配同一个参考对象。

## 仅使用单帧活体推理

已有取帧、检测和追踪流程时，可以直接复用原图人脸框：

```dart
final engine = FaceLivenessEngine();
await engine.initialize();
final frameResult = await engine.evaluateFrame(originalCameraFrame, faceDetection);
print(frameResult.liveScore);
await engine.close();
```

人脸框必须对应这张原图，完整位于画面内，宽高至少 80 像素。
单帧接口不会输出整体通过结论；调用方须做多帧追踪及身份绑定。多人流程必须为每个追踪对象维护独立状态，不能拼接不同人的结果。

## 示例与速度测量

仓库内已有活体 App demo，直接使用取景器中的人脸查询服务器，无需本地参考照片：

```sh
flutter run -t lib/main_liveness.dart -d <Android或iPhone设备ID> \
  --dart-define-from-file=verification/server-deployment/app-defines.json
```

示例复用静态 demo 的 `FaceApi`、HTTPS 证书和服务配置。取景器原图供本地检测与活体推理使用，仅在单帧活体通过后发送人脸特征到 `/v1/search`。连续至少 3 帧、跨度不少于 600ms，同时通过活体并匹配同一业务标记后，才显示服务器返回的业务标记。画面需保持单人；相册查询入口在活体模式下隐藏。界面显示活体分数、观察进度、本地活体耗时以及服务器查询耗时。

App 编排位于 `lib/server_liveness_verifier.dart`；本 SDK 仍不包含网络请求。没有人脸、多人、低活体分数、身份改变、无匹配、歧义或网络错误会重置确认；暂停、切换相机、后台切换会使进行中的结果失效。超过 1.5 秒的旧帧响应不显示通过结果。

当前 Flutter 生成的 iOS Swift Package 最低版本偶尔回落到 15；本仓库提供
`scripts/build_liveness_ios.sh`，会将生成配置与已有项目的 iOS 16 要求对齐，并在缓存目录构建模拟器包。Android ARM64 安装包使用 `scripts/build_liveness_android.sh`。两个脚本读取 `FACE_DEFINES_FILE`（默认上述配置文件），并支持 `FLUTTER_BIN`。iOS 真机可设置 `FACE_TARGET=lib/main_liveness.dart` 后使用 `scripts/build_server_ios.sh`，签名参数沿用该脚本要求。
原主入口继续运行静态服务器检索 demo。

建议每秒处理 5–10 帧，推理忙时丢弃新帧，不建立等待队列。
先预热再统计 P50 / P95，同时记录首次加载、完整确认时间和持续运行后的速度。
`MODEL_MANIFEST.json` 与 `MODEL_CONTEXT_MANIFEST.json` 中是桌面 CPU 合成输入的推理测试，**不是手机实测值，也不是活体准确率报告**。

## 边界与验证

这是 RGB 被动防伪模型，不验证相机输入的可信来源。把旧照片伪装成连续输入不能作为可信活体流程。
尚未完成业务场景下的真人、纸张、屏幕重放、不同机型和光照校准；不能宣称已达到支付或身份核验认证级别。
本包采用两模型活体分数的最小值，要求两者均达到阈值，与上游平均融合不同，不沿用其准确率结论。

## 开发与模型来源

- SDK 代码 MIT；模型及裁剪逻辑来源为 Minivision Apache-2.0，见 `THIRD_PARTY_NOTICES.md`。
- `tool/export_model.py` 固定源提交和 SHA-256，导出 ONNX 并核对数值及测速。
- `MODEL_MANIFEST.json` 记录文件哈希、大小、版本和转换结果。
- 维护者与 AI Agent 详细约束见 `AGENT_GUIDE.md`。
