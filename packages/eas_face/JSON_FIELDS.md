# JSON 结果字段说明

页面“复制 JSON”与 SDK 的 `result.toJsonString(threshold: 0.60)` 输出相同结构。`threshold` 参数使用 0～1 的尺度，例如 0.60 表示 60%。

## 顶层字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `likenessPercent` | number | 模型换算相像百分比，范围 0.00～100.00。 |
| `thresholdPercent` | number | 当前通过标准，例如 60.00。 |
| `passed` | boolean | 是否达到当前通过标准。 |
| `elapsedMs` | number | 本次比对耗时，单位为毫秒，可能包含本次触发的模型初始化。 |
| `first` | object | 第一张照片（参考照片）的人脸框与五点坐标。 |
| `second` | object | 第二张照片（比对照片）的人脸框与五点坐标。 |

## 每张照片的详细数据

`first` 和 `second` 均只包含 `faceBox` 与 `landmarks`。默认输出两侧最大人脸的框和关键点。`FaceEngine(compareAllFaces: true)` 时，输出全部可用组合中得分最高那一组的框和五点；`passed` 表示是否存在至少一组达到指定阈值。全部不达标时仍输出最高分组合，passed 为 false。

| 字段路径 | 类型 | 说明 |
| --- | --- | --- |
| `faceBox` | object | 选中人脸在原图中的检测框。 |
| `faceBox.x` | integer | 人脸框左上角 x 坐标。 |
| `faceBox.y` | integer | 人脸框左上角 y 坐标。 |
| `faceBox.width` | integer | 人脸框宽度。 |
| `faceBox.height` | integer | 人脸框高度。 |
| `landmarks` | array | 五个关键点，固定顺序见下表。 |
| `landmarks[].name` | string | 点位名称。 |
| `landmarks[].x` | integer | 点位横坐标。 |
| `landmarks[].y` | integer | 点位纵坐标。 |

| 顺序 | name | 含义 |
| --- | --- | --- |
| 1 | `imageLeftEye` | 图像左侧眼睛 |
| 2 | `imageRightEye` | 图像右侧眼睛 |
| 3 | `nose` | 鼻尖 |
| 4 | `imageLeftMouth` | 图像左侧嘴角 |
| 5 | `imageRightMouth` | 图像右侧嘴角 |

## 坐标与精度

- 坐标均相对于 EXIF 方向校正后的原图，左上角为原点，x 向右、y 向下；单位为像素，左右指图像方向。
- 点位、人脸框坐标和宽高取最近整数像素，不强制裁剪到图像边缘。
- 相像百分比、通过标准、耗时固定保留两位小数，仍为 JSON 数字。`toJson()` 返回 Map；如需固定末尾零的文本，使用 `toJsonString()`。
- `passed` 使用内部未舍入分数判断，极接近阈值时请以此字段为准，不要用舍入后的数值重新判断。
- JSON 不再输出版本、坐标系标记、分数类型、余弦分数、人脸数量、图片尺寸、置信度及小图点位。SDK 原有属性继续可用；小图点位可通过 `result.first.alignedLandmarks` / `result.second.alignedLandmarks` 单独获取。
