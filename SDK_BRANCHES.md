# SDK 分支说明

| 分支 | 已提交内容 |
| --- | --- |
| `main` | 默认主分支，`packages/eas_face`，0.2.1，纯人脸比对 |
| `feat-eas-face` | 基础 SDK 开发分支，`packages/eas_face`，0.2.1，不含活体扩展 |
| `feat-eas-face-liveness` | 同一份 `eas_face`，加 `packages/eas_face_liveness`，0.1.1，带活体检测 |

活体分支从纯比对分支派生；其基础 SDK 目前停留在 0.2.0，0.2.1 仅更新文档与包信息。两个包的源码、声明使用的模型、许可证、测试和文档均纳入版本控制。

本次分支范围为 SDK。仓库根目录原有应用、服务端、数据库、私人测试输入及构建缓存未纳入这些初始提交，仍保留在本机。切换 Git 分支不会替换未跟踪的应用文件；使用对应分支下的 `packages/` 接入 SDK，纯比对示例位于 `packages/eas_face/example/`。

Git 远端：`https://github.com/CrazyBoyKevin/eas-face.git`，三个分支均已推送，GitHub 默认分支为 `main`。

`eas_face 0.2.1` 已发布到 pub.dev，包含英文 README 和 GitHub 仓库地址。活体扩展尚未发布。
