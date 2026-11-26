# 原型验收记录

2026-11-26，Xcode 27.2（27B52），Apple Swift 6.4.2，部署目标 iOS/iPadOS 17.0。首轮测试发现 SwiftData 模型属性与底层存储的 objectID 冲突。将相机对象句柄命名为 objectHandle 后，重新执行完整套件。以下为最终源码的验证范围。

| 项目 | 环境 | 结果 |
| --- | --- | --- |
| Debug 构建及测试 | iPhone 18 Pro Max 模拟器，iOS 27.0 | 8 项 Swift Testing、2 项 XCTest UI 全部通过 |
| Debug 构建及测试 | iPad Air 11-inch (M4) 模拟器，iPadOS 27.0 | 同一套 10 项全部通过 |
| Release 构建 | generic/platform=iOS，arm64，CODE_SIGNING_ALLOWED=NO | 通过。已编译设备版可执行文件、Assets.car、iPhone/iPad 图标、测试 JPEG 及第三方许可 |
| 文档 | 两份 README、工程文档 | 浏览器使用 Mermaid 11 渲染 15 个图块（架构文档 9 个，每份 README 各 3 个），本仓库相对链接检查通过 |
| 图标 | 原仓库图像与 App 资源逐字节比对 | AppIcon 为不透明 1024 × 1024 PNG。SHA-256 为 71760a4b4b2609a4ce2cdcec0afb2fd9946536392c86bc07cebb194d154c686e。README 的 512 × 512 PNG 由原 SVG 导出 |

## 测试覆盖

- 对照固定字节序列核验 PTP/IP 操作帧，拒绝截断的数据集及错误的字符串终止符。
- 核对可输入的相机局域网地址范围，读取七款独立能力档案。
- 使用回环 TCP 建立命令和事件连接，读取相机信息、存储卡、文件列表和缩略图。原片经过实际客户端，接收端使用 SHA-256 比对测试 JPEG 的源字节。
- 在 responder 发送部分数据时关掉 TCP。检查部分文件和持久化进度，重试后比较全部字节，成功时仅保留一个完成记录。
- 在传输中注入 Wi-Fi 路径变化。核验重复连接请求被合并、部分数据保留、重建会话和从零重传。另一台模拟相机即使返回相同的文件名与大小，GUID 不同也会停止重传。
- XCTest 从 Camera 进入图库、取缩略图、下载原片，并在 Transfers 验证 Saved 和相册导出入口。另一个界面测试验证无效地址反馈及 Nikon Z8 能力档案。

测试 JPEG 为 71,015 字节，SHA-256 为 a325cec5f3455703374aee9732d386fd47f91e04869d07d638e0a9aaed1a24c7。链路测试走真实回环套接字，Wi-Fi 路径变化由测试注入。正常启动时的文件和测试用临时目录相互隔离。

## 待验收

七款实体相机与固件、设备签名安装、真实 BLE 配对和热点加入、真实系统相册写入、NEF/视频、后台或关机后传输、真机性能与功耗、TestFlight 及 App Store 发布均待验收。下一次现场试验先验证一个机身与固件的一张 JPEG，随后中途断开热点并复核卡上原件的哈希。[机型记录](compatibility.md) · [现场步骤](roadmap.md)
