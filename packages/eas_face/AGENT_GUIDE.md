# eas_face — AI Agent 技术指南

适用版本：`eas_face 0.2.0`。文档更新：2026-10-19。

本文供 AI Agent 接入、排查和维护 SDK 使用。面向开发者的快速接入见 [README](README.md)，JSON 的字段约定见 [JSON_FIELDS](JSON_FIELDS.md)。本文记录当前实现及维护建议，不代表每次任务都需要修改所有模块；执行范围以用户当前要求为准。

## 1. 项目定位与边界

- Flutter Android/iOS 的本地一对一人脸比对；输入两张文件字节，默认分别选择面积最大的人脸；compareAllFaces=true 遍历两侧所有可用组合。
- SDK 不发起照片上传、云端识别、账号登录，不负责拍照、选择相册或权限申请。
- 检测器为 YuNet，识别器为 Intel 0095 FP32 ONNX；两份资源随包分发，运行时无需下载模型。
- 不提供活体检测。显示百分比是应用定义的分数尺度，不是身份概率或实测准确率。
- SDK 不支持 Web。完整开发仓库中的浏览器适配器用于开发验证，不属于 SDK 的平台支持承诺。
- 当前名称和版本以 `pubspec.yaml` 为准；本文和 README 不作为包已公开发布的证明。

## 2. 建议阅读顺序与源码定位

| 任务 | 首先阅读 | 相关测试/资料 |
| --- | --- | --- |
| 集成调用、结果导出 | `lib/eas_face.dart`、`lib/src/face_engine.dart` | 本文第 3 节、`JSON_FIELDS.md` |
| 分数、阈值、百分比 | `lib/src/face_score.dart` | `test/face_threshold_test.dart` |
| 检测框、五点与对齐 | `lib/src/face_math.dart`、`lib/src/face_engine.dart` | `test/face_math_test.dart`、`test/aligned_landmarks_test.dart` |
| 图片采样、通道与尺寸 | `lib/src/image_tensor.dart` | `test/image_tensor_test.dart` |
| 缓存与生命周期 | `lib/src/photo_cache.dart`、`lib/src/face_engine.dart` | `test/photo_cache_test.dart` |
| 点位组件 | `lib/eas_face_widgets.dart`、`lib/src/face_landmarks.dart` | `test/face_landmarks_test.dart` |
| Android/iOS 接入 | `example/` | `example/README.md` |
| 模型来源与转换 | `tool/`、`THIRD_PARTY_NOTICES.md` | 模型校验值、`licenses/` |

本包的路径均相对于 SDK 根目录。完整开发仓库将 SDK 放在 `packages/eas_face/`，根应用通过 path 依赖引用。只持有 SDK ZIP 的调用方没有仓库根应用及其脚本，不应假定这些文件存在。

## 工作区实时与多人 API 补充（2026-10-16）

- `compareImage(referenceBytes, image)`：接收正向非镜像 `package:image` 图像；与 compare 一样受 compareAllFaces 控制。
- `searchImage(referenceBytes, image)`：检测全图一次，逐个提取可用人脸，返回 `FaceSearchResult`，候选按原始余弦分数降序排列。
- `FaceSearchResult` 提供 `candidates`、`best`、`matches(threshold)`、`detectedFaceCount`、`skippedFaceCount` 和 `elapsed`。`best` 并不意味着已达到阈值。
- 原始帧结果 `second.preview` 为空，使用相机预览；检测坐标和对齐预览保留。参考缓存、串行调用、模型配置与旧流程一致。
- Demo 仅在唯一候选达标、位置连续且连续三次确认时显示匹配；多人同时达标提示歧义。
- 下文原有的“最大脸”与文件输入描述主要针对旧 `compare` 接口，不应套用到 `searchImage`。

## 3. 完整公开 API 参考

下面按方法、对象字段和 JSON 分开列出。`lib/src/` 是实现目录，接入代码应优先使用两个公开入口；新增 API 时同步检查入口导出。

### 接口方法

以下接口通过 `package:eas_face/eas_face.dart` 导入。方法负责执行操作；返回对象的字段在下一节逐项说明。

#### FaceEngine：模型与比对

使用 `FaceEngine()` 默认选择两侧最大脸，`FaceEngine(compareAllFaces: true)` 比较全部可用组合。现有偏色、光照及有限几何校正始终自动执行。

| 构造参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `compareAllFaces` | `bool` | `false` | 不可变配置；compare / compareImage 遍历两侧人脸组合并返回最高分一组。 |

| 方法 | 返回类型 | 用途 |
| --- | --- | --- |
| `initialize()` | `Future<void>` | 加载内置模型；重复调用复用初始化任务，初始化失败后可以重试。 |
| `compare(first, second, {onProgress})` | `Future<FaceComparison>` | 比对两张照片，返回结果；未初始化时自动初始化。 |
| `retainCachedPhotos(photos)` | `void` | 仅保留指定照片的已有缓存；传入空列表清空缓存，不会预先分析照片。 |
| `close()` | `Future<void>` | 释放模型会话和照片缓存；调用前等待当前初始化或比对结束。 |

`compare` 参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `first` | `Uint8List` | 是，位置参数 | 第一张照片的完整文件字节。 |
| `second` | `Uint8List` | 是，位置参数 | 第二张照片的完整文件字节。 |
| `onProgress` | `void Function(String)?` | 否，命名参数 | 接收处理阶段文字；这是阶段提示，不是进度百分比。 |

`retainCachedPhotos` 的 `photos` 类型为 `Iterable<Uint8List>`，传入当前仍需保留的照片文件字节集合。一个引擎最多缓存两张照片；同一实例的 `compare` 不允许并发调用。

#### FaceComparison：判断与导出

以下方法由 `engine.compare(...)` 返回的 `result` 调用。

| 方法 | 返回类型 | 参数与行为 |
| --- | --- | --- |
| `matches(double threshold)` | `bool` | `threshold` 是必填位置参数，使用 0～1 尺度；例如 `result.matches(0.60)` 判断是否达到 60%。 |
| `toJson({double threshold = defaultThreshold})` | `Map<String, Object>` | `threshold` 为可选命名参数，默认 `0.60`；返回精简 JSON 数据结构。 |
| `toJsonString({double threshold = defaultThreshold})` | `String` | 参数同上；返回缩进排版的 JSON 文本，百分比和耗时固定两位小数，坐标为整数。 |

通过判断使用未舍入的 `likeness >= threshold`。参数传 `0.60`，不要传 `60`。

#### FaceSample：单张照片导出

| 方法 | 返回类型 | 用途 |
| --- | --- | --- |
| `toJson()` | `Map<String, Object>` | 导出该照片选中人脸的 `faceBox` 和 `landmarks`，坐标取整；不包含照片字节、特征向量或小图点位。 |

#### 分数辅助函数

| 函数 | 返回类型 | 输入与用途 |
| --- | --- | --- |
| `likenessScore(double cosine)` | `double` | 将原始余弦分数换算成 0～1 的显示分数；通常直接读取 `result.likeness` 即可。 |
| `formatLikeness(double score)` | `String` | 将 0～1 的显示分数格式化为两位小数的百分比，例如 `formatLikeness(0.752)` 返回 `75.20%`。 |

### 返回对象与字段

Dart 对象保留原始数值精度；下文的对象字段与 JSON 导出字段分开列出。

#### FaceEngine 状态属性

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `compareAllFaces` | `bool` | 构造时设定的只读多人组合开关。 |
| `isReady` | `bool` | 两个模型会话是否都已加载完成，只读。 |

#### FaceComparison：一次比对结果

访问示例：`result.likeness`、`result.first`。

| 字段 | 类型 | 范围或单位 | 说明 |
| --- | --- | --- | --- |
| `likeness` | `double` | 0～1 | 模型换算后的显示分数；显示百分比时使用 `formatLikeness`。 |
| `cosine` | `double` | −1～1 | 原始余弦分数，供评测使用；精简 JSON 不导出此字段。 |
| `elapsed` | `Duration` | 时间间隔 | 本次比对总耗时，包含本次实际发生的模型初始化与照片处理。 |
| `first` | `FaceSample` | — | 第一张输入照片的处理结果。 |
| `second` | `FaceSample` | — | 第二张输入照片的处理结果。 |

#### FaceSample：单张照片的人脸数据

访问示例：`result.first.detection`、`result.second.alignedPreview`。默认选择面积最大的人脸；compareAllFaces=true 时选择最高分组合中的对应人脸。

| 字段 | 类型 | 单位或格式 | 说明 |
| --- | --- | --- | --- |
| `width` | `int` | 像素 | EXIF 方向校正后的原图宽度。 |
| `height` | `int` | 像素 | EXIF 方向校正后的原图高度。 |
| `faceCount` | `int` | 个 | 全图检测到的人脸数量。 |
| `detection` | `FaceDetection` | — | 选中人脸在原图中的检测框、置信度和五点坐标，详见下表。 |
| `preview` | `Uint8List` | 原始图片文件字节 | 输入照片的只读副本，可用于图片展示；并非重新编码后的方向校正图。 |
| `alignedPreview` | `Uint8List` | PNG 文件字节 | 选中人脸的 128×128 对齐小图，只读。 |
| `alignedWidth` | `int` | 像素 | 对齐小图宽度，当前为 128，只读属性。 |
| `alignedHeight` | `int` | 像素 | 对齐小图高度，当前为 128，只读属性。 |
| `alignedLandmarks` | `List<FacePoint>` | 小图像素坐标 | 五点经同一对齐变换映射到小图后的坐标，只读列表。 |
| `embedding` | `List<double>` | 256 维向量 | 选中人脸的特征，只读列表，不应写入普通日志。 |

#### FaceDetection：原图人脸框

访问示例：`result.first.detection.x`。

| 字段 | 类型 | 单位或范围 | 说明 |
| --- | --- | --- | --- |
| `x` | `double` | 像素 | 人脸框左上角横坐标。 |
| `y` | `double` | 像素 | 人脸框左上角纵坐标。 |
| `width` | `double` | 像素 | 人脸框宽度。 |
| `height` | `double` | 像素 | 人脸框高度。 |
| `score` | `double` | 0～1 | 人脸检测置信度，与两张照片的相似分数含义不同。 |
| `landmarks` | `List<FacePoint>` | 原图像素坐标 | 选中人脸的五个关键点，SDK 返回只读列表。 |

#### FacePoint：单个关键点

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `x` | `double` | 点位横坐标，向右增大。 |
| `y` | `double` | 点位纵坐标，向下增大。 |

坐标原点均为图片左上角。`detection.landmarks` 相对于 EXIF 方向校正后的原图；`alignedLandmarks` 相对于对齐小图。两种列表的顺序一致：

| 列表下标 | JSON 点位名称 | 含义 |
| --- | --- | --- |
| `0` | `imageLeftEye` | 图像左侧眼睛。 |
| `1` | `imageRightEye` | 图像右侧眼睛。 |
| `2` | `nose` | 鼻尖。 |
| `3` | `imageLeftMouth` | 图像左侧嘴角。 |
| `4` | `imageRightMouth` | 图像右侧嘴角。 |

左右指图像方向。`FacePoint` 本身只有 `x`、`y`，点位名称由 JSON 导出方法按列表顺序添加。

#### 公共常量

| 名称 | 类型 | 当前值 | 用途 |
| --- | --- | --- | --- |
| `defaultThreshold` | `double` | `0.60` | 默认显示分数通过线，即 60%。 |
| `recognitionReferenceCosine` | `double` | `0.4` | 当前模型的原始参考点，在显示尺度上映射为 60%。 |
| `maxFileBytes` | `int` | `15728640` | 单张图片文件大小上限，15 × 1024 × 1024 字节。 |
| `sfaceReferenceCosine` | `double` | `0.363` | 已弃用，仅保留用于旧 SFace 结果迁移，当前模型不使用。 |

### JSON 导出字段

`result.toJson()` 返回 Map，`result.toJsonString()` 返回文本。完整嵌套字段解释见 [JSON_FIELDS.md](JSON_FIELDS.md)。

| 顶层字段 | JSON 类型 | 说明 |
| --- | --- | --- |
| `likenessPercent` | number | 模型换算百分比，0.00～100.00。 |
| `thresholdPercent` | number | 导出时指定的通过标准，例如 60.00。 |
| `passed` | boolean | 使用内部未舍入分数计算的通过结果。 |
| `elapsedMs` | number | 本次比对耗时，单位毫秒。 |
| `first` | object | 第一张照片的原图人脸框与五点坐标。 |
| `second` | object | 第二张照片的原图人脸框与五点坐标。 |

`first` 和 `second` 各自只有两个字段：

| 字段 | 内容 | 坐标精度 |
| --- | --- | --- |
| `faceBox` | `x`、`y`、`width`、`height` | 原图整数像素。 |
| `landmarks` | 五个对象，每个包含 `name`、`x`、`y` | 原图整数像素。 |

JSON 不包含小图点位；小图及点位通过 `FaceSample` 的对应属性获取，示例见下节。

### 输入限制与异常

单张图片不超过 `maxFileBytes`、2400 万像素；支持 JPG/PNG/WebP，不直接解码 HEIC。相册选择器若给出 HEIC，接入方应先在本地转换为支持的格式。

| 情况 | 异常或处理 |
| --- | --- |
| 在 Android/iOS 以外的平台初始化 | 抛出 `UnsupportedError`。 |
| 图片格式错误、无脸或人脸太小 | 抛出 `FormatException`。 |
| 同一引擎并发比对，或比对中调用 `close()` | 抛出 `StateError`。 |
| 模型加载、推理或其他运行环境错误 | 向调用方传播对应异常，需要捕获处理。 |

失败可再次调用；不要把所有异常当成“不同人”。照片选择、拍照、权限请求和业务结果处理由宿主应用控制。


## 4. 调用时序、状态与资源所有权

推荐时序：创建 `FaceEngine` → 初始化 → 串行比对 → 按需清理照片缓存 → 等待操作结束 → 关闭。

- 构造实例不会立即创建模型会话；`isReady` 仅表示两个会话都存在，不表示输入照片已处理。
- `initialize()` 复用 `_loading` 任务。加载失败时清理模型并重置加载状态，后续可重试。
- `compare()` 在初始化前设置忙状态，以 `finally` 清除；并发调用抛 `StateError`。
- 两张照片按顺序提取。`onProgress` 在各侧提取前调用，即使命中缓存也可能收到阶段提示；回调应轻量，不要从回调中再次调用比对。
- `elapsed` 从本次 `compare` 开始计时；冷启动、缓存命中与首次解码会影响耗时，不能将热缓存耗时当作完整推理耗时。
- 缓存按完整字节内容匹配并保存输入副本，最多两项，命中时更新使用顺序。不会仅凭文件名、对象地址或弱哈希判定相同照片。
- 每次 `compare` 自动仅保留两张当前输入对应的缓存。`retainCachedPhotos` 只筛选已有缓存；空集合清空。
- SDK 返回的文件字节、特征列表和关键点列表为只读数据。公开构造函数允许调用方自行构造对象；不要据此假定任意手工构造的实例都具有 SDK 返回对象的有效性。
- 调用方仍持有 `FaceComparison` 或 `FaceSample` 时，关闭引擎不等于这些对象已从调用方内存释放。
- `close()` 在比对忙碌时拒绝执行；等待初始化后关闭会话并重置状态。宿主负责安排任务完成顺序，不要在同步 `dispose()` 内假设异步清理已完成。
- `createModelSession(String assetPath)` 为带 `@protected` 的扩展点，返回 `Future<OrtSession>`；普通调用方不需要调用或覆盖。默认平台检查发生在该方法中。

## 5. 本地推理流水线

### 5.1 文件校验与方向

1. 拒绝空文件和超过 `15 * 1024 * 1024` 字节的文件。
2. 读取解码信息，检查宽高为正且总像素不超过 24,000,000。
3. 解码第 0 帧，使用 `bakeOrientation` 处理 EXIF 方向；后续检测与坐标都基于该图。
4. 保留校正后的原分辨率像素，用于小脸复检与最终对齐。`preview` 则保留原输入文件字节副本，并非这些像素的重新编码。

对外文档列出 JPG/PNG/WebP，不承诺 HEIC；实现使用 image 包的解码器发现机制，不是严格的三种扩展名白名单。新增格式支持承诺前应验证实际解码与方向处理。

### 5.2 YuNet 检测与最大脸选择

- 输入为 Float32、BGR、NCHW，形状 `[1, 3, 640, 640]`。
- 长边缩放到 640；短边四舍五入，右侧/底部补零，不做居中补边。
- 使用半像素中心双线性采样。恢复原图坐标时，分别使用实际缩放宽高计算 x/y 比例，避免舍入偏差。
- 解码后排除中心落在补边区域的脸；保留检测按面积、置信度、检测顺序排序；默认取首张，compareAllFaces=true 遍历全部。
- 原图框宽高中较小者不足 60 像素时拒绝处理。
- `faceCount` 是全图这一轮检测后保留的数量，不是局部复检的候选数量。

### 5.3 小证件人像复检

当首次检测空间中选中框的较大边小于 160 像素时，围绕原图人脸框外扩并裁剪局部区域，重新执行 YuNet。局部框和关键点通过缩放及裁剪偏移映射回原图。

只接受与原选中框 IoU 大于 0.5 的候选，并取重叠最高者。没有满足条件的候选时保留初次结果，避免切换到邻近人像或水印。

### 5.4 五点对齐与识别

- 标准分支的 `fitRecognitionAlignment` 使用 Intel 五点参考位置及 RMS 尺度约定；变换包含旋转、统一缩放和平移，不增加剪切或镜像。
- 从原图逆变换采样得到 128×128 人脸小图；双线性插值，图像外为黑色边界。
- 识别张量为 Float32 BGR/NCHW，形状 `[1, 3, 128, 128]`，输入为原始像素数值，当前实现对插值后的通道取整。
- ONNX 图内已包含归一化，不要额外使用 RGB、除以 255 或套用其他识别器的 mean/std。
- 输出必须为 256 维，并通过余弦函数校验非零及有限性。
- `alignedLandmarks` 对原图检测点应用同一变换；不能用参考模板点替换真实变换后的点位。
- `_infer` 管理 OrtValue 释放并按句柄去重；运行时返回重复句柄时有限次重试，不能通过跳过释放掩盖问题。

### 5.5 自动几何容错

实现：`lib/src/document_tolerance.dart`；回归：`test/document_tolerance_test.dart`。

1. 有限几何校正自动执行，不再提供 documentTolerance 构造参数或属性。
2. 在标准对齐五点上拟合带单位矩阵先验的仿射残差；中心化后 ridge = 30²，允许有限非等比缩放及剪切。两张图片独立处理，不读取对方特征或比较分数。
3. 非五点、非有限坐标、退化协方差、非正行列式均跳过几何修正，保留偏色/光照辅助。线性变换奇异值需位于 [0.8, 1.25]，最大点位位移需位于 [0.05, 8] 个小图像素；越界沿用标准分支。
4. 合成两个逆变换，直接从原图双线性采样辅助 128×128 BGR 张量，避免先生成标准图再进行二次插值。
5. 辅助与标准特征分别 L2 归一化，等权求和后再次归一化。无最高分挑选、阈值降低或百分比映射更改。辅助特征无效时抛错，不返回伪分数。
6. `alignedPreview` 与 `alignedLandmarks` 始终表示标准对齐结果；辅助图仅参与特征计算，不替换对外图像或坐标。原图 faceBox、landmarks 和精简 JSON 不变。
7. 每张可用人脸生成两个识别输入，单位特征等权融合；照片缓存保持两张。持久化特征须记录流水线及模型版本，不能混用旧版特征。

这不是完整的证件四角透视矫正或纸张曲面展开。五点无法恢复折痕、遮挡、反光丢失的像素；有限校正也不保证所有照片得分更高。不要因为只有两个人的合成控制样例通过就声称业务准确率提升。

### 5.6 实验性偏色辅助

实现：`lib/src/document_photometric.dart`，测试：`test/document_photometric_test.dart`。

- 偏色和有限光照归一化内部自动启用，不再提供 documentColorTolerance 构造参数或属性。演示无开关；不从文件名、分数或一方照片自动推断启用条件。
- 辅助张量先用有限几何校正（校正有效时），否则复用标准几何张量；以 `0.114 B + 0.587 G + 0.299 R` 计算亮度，三个输出通道均使用同一亮度。
- 统计排除纯黑填充和纯白裁切；有效像素至少 32，5%～95% 亮度跨度至少 16 时才做 tone 调整。gain = clamp(192/span, 0.8, 1.5)，offset = clamp(128 - gain*(low+high)/2, -24, 24)。输出截断至 0～255 并取整，黑白裁切区域保留。近乎纯色区域仅去色，避免放大噪声。
- 不修改原始 tensor、公开预览、标准对齐小图或点位；仅替换辅助视图的张量。标准和辅助特征仍等权融合。每张脸的辅助视图额外一次识别推理，不新增模型依赖或云请求。
- 测试使用合成 BGR 色块、灰阶、填充、平坦区域和非法数值。没有对当前用户照片执行身份比对或调分；未评测此模式的 FAR/FRR 或移动端性能。此前几何模式的回归数字不能当作偏色模式的效果证据。
- 存储向量时必须标记模型及预处理流水线版本。不能将此算法描述为恢复真实肤色、去防伪纹理、去折痕或身份概率校准。

### 5.7 多人组合选择

- `compareAllFaces` 是构造时不可变 bool，默认 false；compare、compareImage 共用 `bestFacePair`，完整计算可用两侧集合的笛卡尔积。
- 每张图检测一次，按面积降序、置信度降序、原检测顺序排序；默认只提取首张且错误直接抛出。多人模式遍历所有检测，FormatException（尺寸/对齐）跳过；其他运行时异常立即传播。全部不可用时抛带照片标签的 FormatException。
- `PhotoCache<List<FaceSample>>` 缓存最多两张照片的人脸集合。照片内各脸共享一份只读原文件预览；小图和特征各自保存。帧不进入缓存；searchImage 保留独立语义：参考取最大可用脸，帧返回全部候选。
- 最高原始余弦对应最高 likeness，任意阈值下 `best.matches(t)` 等价于所有组合中至少一个达标。不得先四舍五入、提前遇到达标返回，或把无有效脸当成零分。
- `first`/`second` 始终是获选组合，所有坐标、小图、overlay 和 JSON 必须由这两个对象产生。精简 JSON 不新增字段，faceCount 保留检测总数（含跳过项）。
- 没有新增人数硬上限；提取约 O(N+M)，组合 O(N*M)，内存随人脸数增长。人数增加时任意匹配的误通过率需要业务重新评估，现有阈值不是多人业务校准值。
- `test/multi_face_comparison_test.dart` 使用模拟 ONNX 输出、合成色块及特征向量覆盖整个 Dart 调用链，验证任意侧多人、双侧小脸命中、全不匹配、缓存、空/小脸、资源释放、异常和原始帧。它不证明真实模型识别准确率。

## 6. 分数与 JSON 不变量

### 6.1 分数换算

设原始余弦分数经 `[0, 1]` 截断后为 `c`，显示分数为 `s`：

```text
c <= 0.4: s = c / 0.4 * 0.60
c >  0.4: s = 0.60 + (c - 0.4) / 0.60 * 0.40
百分比 = s * 100
通过 = s >= threshold
```

原始 0、0.4、1 分别映射为 0%、60%、100%；负分显示 0%。`likenessScore` 拒绝非有限输入。0.4 是当前模型的参考点，不是护照业务样本校准结果。

`matches` 和 JSON 导出当前没有对 threshold 做范围校验或自动截断，宿主应传入有限的 0～1 数值。不要声称 SDK 会自动把 60 转为 0.60。修改参数校验属于行为变化，需要单独验证。

不要为迎合单组照片或其他厂商分数而抬高映射。模型更换或阈值校准应使用同人/异人样本及独立验证集；不同模型分数不能直接比较。

### 6.2 导出契约

- 顶层仅有 `likenessPercent`、`thresholdPercent`、`passed`、`elapsedMs`、`first`、`second`。
- 每侧仅有 `faceBox` 和 `landmarks`；没有图片字节、特征向量、模型信息或小图坐标。
- 框的 x/y/width/height 和关键点 x/y 使用 `round()`，不强制裁剪到图片范围。
- `passed` 根据未舍入的分数计算。不要先四舍五入百分比再判断。
- `toJson()` 的数字维持数值类型，不承诺显示末尾零；固定两位小数的文本使用 `toJsonString()`。
- `_formatResultJson` 根据顶层字段位置决定两位小数，不依赖运行时区分 int/double；开发环境中的 JavaScript 数字表示会合并这两类。
- 结构改变时同时更新 `JSON_FIELDS.md`、README 和严格字段集合测试。

## 7. 展示与坐标对应

`FaceLandmarkOverlay` 接收 `imageSize: Size`、`points: List<FacePoint>`、`matches: bool` 三个必填命名参数，可选 `key`。它不自行执行比对，只根据 matches 选择绿色或红色，按居中 `BoxFit.contain` 计算缩放和留白，不显示坐标数字。

| 展示内容 | 图片数据 | 尺寸 | 点位 |
| --- | --- | --- | --- |
| 原图 | `preview`，展示器需正确处理 EXIF | `width` / `height` | `detection.landmarks` |
| 对齐小图 | `alignedPreview` | `alignedWidth` / `alignedHeight` | `alignedLandmarks` |

不要将原图点位叠加在小图，或在 `BoxFit.cover`、额外裁剪、镜像后直接复用 contain 变换。原图 preview 仍为输入文件字节；自定义显示器必须保证与 SDK 方向校正后的坐标一致。点位可能出界，若产品需要，应在显示层裁剪，而不是篡改用于评测或导出的原始坐标。

## 8. 模型、依赖与分发

| 项目 | 当前配置 |
| --- | --- |
| 包名 / 版本 | `eas_face` / `0.2.0` |
| Dart / Flutter 最低声明 | Dart `>=3.7.0 <4.0.0` / Flutter `>=3.29.0` |
| 移动平台 | Android API 24+；iOS 16+ |
| 运行时 | `flutter_onnxruntime: 1.9.0`，原生会话线程参数为 intra=2、inter=1 |
| 图像依赖 | `image: ^4.5.4`，实际解析版本见锁文件 |
| YuNet 资源 | `assets/models/face_detection_yunet_2023mar.onnx` |
| Intel 资源 | `assets/models/face-reidentification-retail-0095.onnx` |
| 资源加载前缀 | `packages/eas_face/assets/models/` |
| 许可加载前缀 | `packages/eas_face/licenses/` |

两份模型合计约 4.48 MiB，SDK 依赖的原生运行库会增加宿主 App 体积，不能把模型体积当作最终 App 增量。

### 模型再生成

普通接入不需要 Python 或 OpenVINO。只有维护者重新生成模型时，在 SDK 根目录运行：

```bash
python3.12 -m venv .model-env
.model-env/bin/pip install -r tool/conversion-requirements.txt
.model-env/bin/python tool/download_models.py
```

YuNet 使用固定 OpenCV Zoo commit。Intel 使用固定 2023.0 FP32 IR，经 openvino2onnx 1.1.0 转为 ONNX opset 17 / IR 9；源 IR 校验 SHA-384，输出校验 SHA-256。来源、转换声明与当前 hash 见 `THIRD_PARTY_NOTICES.md` 及转换脚本。转换属于开发阶段，App 运行时不执行这些工具。

### 交付内容

- 显式声明两份模型资源，避免将工作区中的旧 SFace 模型带入包。
- 保留 MIT LICENSE 和第三方许可证，不能用 SDK 的 MIT 许可证替代模型自身许可。
- `.pubignore` 排除内部验证记录、旧模型、构建产物、个人环境路径及缓存；模型目录的反向规则保证资源不被父级 Git 忽略规则漏掉。
- 完整开发仓库提供 `scripts/package_sdk.py`，生成带逐文件 hash 的 ZIP；独立 SDK 不包含此仓库级脚本。
- 发布前核验实际压缩包，不仅检查源码目录。用户样本、证件照片、特征数据和诊断截图不得混入发布包。
- 发布预检查与正式上传是不同操作；改文档或打 ZIP 不代表已经上传到 pub.dev。

## 9. 验证与完成标准

### 常用命令

在 SDK 根目录执行：

```bash
flutter pub get
flutter analyze
flutter test
```

在 `example/` 执行 `flutter pub get`，然后选择 Android/iOS 设备运行。需要验证原生构建时执行：

```bash
flutter build apk --release
flutter build ios --release --no-codesign
```

iOS 构建要求 macOS 与 Xcode。示例 Android release 使用调试签名，不能视为商店发布产物；iOS 无签名构建不等于真机签名运行。

发布内容预检查在 SDK 根目录执行：

```bash
dart pub publish --dry-run
```

当前缺少 homepage/repository 和锁定单个运行时版本会产生建议性警告。不要为了消除警告捏造仓库地址或无验证地升级原生运行时。

### 按变更选择检查

| 变更 | 有意义的验证 |
| --- | --- |
| 文档整理 | 对照源码核验签名、默认值、单位和示例；检查相对链接及 ZIP 文档同步，无需重复推理测试。 |
| 分数或导出 | 阈值边界、精度、字段集合及 JSON 可解析性测试。 |
| 坐标或对齐 | 原图/小图坐标变换、采样边界与方向测试，必要时用本地授权样本验证真实输出。 |
| 缓存或生命周期 | 相同内容、可变输入、淘汰、清理、失败恢复与并发行为。 |
| 模型或运行时 | 输入布局/归一化检查、真实模型对照、原生构建及目标设备运行。 |
| 包名或资源路径 | SDK/示例/宿主依赖解析、静态分析、测试及归档中模型路径检查。 |

### 已有证据与限制

历史 0.1.1：截至 2026-10-15，SDK 33 项测试与宿主 3 项测试通过；此前仅几何模式的 16 组合成变体及不同人对照 WASM 回归通过，新增偏色模式仅做合成像素测试，不能沿用几何模式的精度结论，静态分析通过。此前模型实现完成过 Android release 和 iOS 无签名构建；改名后没有重新进行原生构建。少量开发控制样例覆盖同图、变换图、不同人、多人大脸、文档小人像和无效输入。

这些记录不代表已完成 Android/iOS 真机性能验证、活体检测或护照业务总体准确率评测。不要将构建通过、单组同人得分或浏览器开发适配器的耗时描述成移动端效果保证。

## 10. 常见误改与交付检查

- 保持本地执行与最大脸选择约定，除非用户明确要求改变。
- 模型、输入通道、归一化、五点顺序及对齐模板必须作为同一套流程验证。
- 原始余弦、0～1 显示分数、0～100 JSON 百分比、检测置信度是四种不同含义，变量与文档不要混用。
- 小图点位来自实际坐标变换；原图 JSON 保持原图坐标，不要按 UI 缩放后导出。
- 文档中给出的接口必须存在于公开入口；不要凭模型名称添加不存在的配置、属性或 Web 支持。
- 修改完成后同步受影响的 README、JSON_FIELDS、CHANGELOG 和交付 ZIP；说明实际运行过的检查及未验证项。
- 本指南只描述维护约定，不授予发布、发邮件或访问其他用户数据的额外授权。
