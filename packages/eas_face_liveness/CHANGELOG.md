## 0.1.1 (local, unreleased)

- Add MiniFASNetV1SE at 4× context alongside MiniFASNetV2 at 2.7×; return the minimum live score and both component scores. Both models must pass, and either runtime failure aborts verification.
- Reject insufficient source context in joint verification and the camera/server demo; do not silently accept close-up faces with less than 2.7× context.
- Record the reported large-screen-photo false acceptance in 0.1.0. These changes are candidates for retesting, not a claim that screen replay is solved.

## 0.1.0

- 新增依赖 eas_face 的本地轻量单模型静默活体检测，支持连续帧确认、身份与活体联合验证，以及分阶段耗时输出。
