# SDK 分支说明

| 分支 | 已提交内容 |
| --- | --- |
| `feat-eas-face` | `packages/eas_face`，0.2.0，纯人脸比对，不含活体扩展 |
| `feat-eas-face-liveness` | 同一份 `eas_face`，加 `packages/eas_face_liveness`，0.1.1，带活体检测 |

活体分支从纯比对分支派生，基础 SDK 保持一致。两个包的源码、声明使用的模型、许可证、测试和文档均纳入版本控制。

本次分支范围为 SDK。仓库根目录原有应用、服务端、数据库、私人测试输入及构建缓存未纳入这些初始提交，仍保留在本机。切换 Git 分支不会替换未跟踪的应用文件；使用对应分支下的 `packages/` 接入 SDK，纯比对示例位于 `packages/eas_face/example/`。

Git 远端：`https://github.com/CrazyBoyKevin/eas-face.git`，两个分支均已推送。

`eas_face 0.2.0` 已发布到 pub.dev；文档后续更新以 GitHub 为准，pub.dev 会在发布新版本后更新。活体扩展尚未发布。
