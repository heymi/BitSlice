# BiCut 竞品与公开价格调研

调研日期：2026-07-11。价格仅记录当日可公开读取的**官方**页面；未使用第三方评测、价格聚合或汇率换算。

## BiCut 对标范围

代码显示 BiCut 是一款 macOS 14+ 的本地单视频分片工具：载入一个视频后，按设定的等时长区间生成多个片段，可预览、逐帧步进、选择 MP4/MOV/M4V、命名与导出目录，并提供原始/720p/1080p/2K/4K 输出。当前所有精确分片输出都走 AVAssetReader/Writer 重编码，以保证切点按视频帧对齐。因此本调研优先比较 macOS 上的「分割、修剪、快速/无损导出」产品，而不是完整专业 NLE。

证据：[`ExportConfig.swift`](../Sources/BiCut/Models/ExportConfig.swift)；[`InspectorSidebarView.swift`](../Sources/BiCut/Views/InspectorSidebarView.swift)；[`VideoProcessor.swift`](../Sources/BiCut/Services/VideoProcessor.swift)。

## 直接可比：macOS 视频分割/裁切

| 产品 | 与 BiCut 的重叠点 | 当前公开价 | 计费与来源 |
| --- | --- | --- | --- |
| [Video Merge & Split](https://apps.apple.com/us/app/video-merge-split/id955365184?mt=12) | 分割、合并、格式/分辨率参数、批量分割 | **US$1.99** | 一次性；美国 Mac App Store。 |
| [iMediaCut – Easy Video Trimming](https://apps.apple.com/us/app/imediacut-easy-video-trimming/id1619693028) | 视频修剪、合并、格式转换 | **免费**；完整解锁 **US$2.99** | 内购；美国 Mac App Store。 |
| [Any Video Splitter](https://apps.apple.com/us/app/any-video-splitter/id961260390?mt=12) | 多片段、按等间隔/指定时长/指定体积、可强制重编码 | **US$3.99** | 一次性；美国 Mac App Store。 |
| [Batch Video Splitter](https://apps.apple.com/us/app/batch-video-splitter/id1294112872?mt=12) | 按时间或文件大小均分，核心任务最接近 | **US$9.99** | 一次性；美国 Mac App Store。 |
| [LosslessCut](https://apps.apple.com/us/app/losslesscut/id1505323402?mt=12) | 极快、无损剪切/分段、片段列表与导出 | **US$18.99** | 一次性；美国 Mac App Store。其[官网](https://losslesscut.app/)同时提供免费、可查看源码的直接下载，因此它也是免费替代品。 |
| [SolveigMM Video Splitter 4](https://apps.apple.com/us/app/solveigmm-video-splitter-4/id1220817427?mt=12) | 无损、帧准确裁切，多个区间、时间线/缩略图/波形 | **US$29.99** | 一次性；美国 Mac App Store。 |
| [TunesKit Video Cutter for Mac](https://www.tuneskit.com/buy/video-cutter-for-mac.html) | 无损修剪、分割、合并与转码 | **US$14.95/月**、**US$29.95/年**或 **US$49.95** 永久版 | 1 Mac；月/年方案为自动续订，永久版为一次性。官方价格页显示为促销价。 |

## 宽口径替代品（不是 BiCut 的同类极简产品）

| 产品 | 为什么会抢同一需求 | 当前公开价 | 计费与来源 |
| --- | --- | --- | --- |
| [iMovie](https://apps.apple.com/us/app/imovie/id408981434?mt=12) | 可在时间线中分割/修剪并导出 4K；随 macOS 生态的免费基线 | **免费** | 美国 Mac App Store；Apple 开发。 |
| [CapCut](https://apps.apple.com/us/app/capcut-photo-video-editor/id1500855883?platform=mac) | 免费编辑器，包含 trim/split/merge；对「只想切视频」的用户是高认知度替代品 | 应用**免费 + 内购**；US Mac 页面列出 **US$9.99/月（Standard）**、**US$19.99/月（Pro）**、**US$89.99/年（Pro）** | 美国 Mac App Store。其[官方说明](https://www.capcut.com/help/how-much-does-capcut-pro-cost)明确价格会随地区、设备和优惠变化。中国区的[剪映专业版](https://apps.apple.com/cn/app/%E5%89%AA%E6%98%A0%E4%B8%93%E4%B8%9A%E7%89%88/id1529999940?platform=mac)为免费+内购，商店描述列连续包月 **¥25**、单月 **¥30**、连续包年 **¥138**、单年 **¥188**。 |
| [VideoProc Converter AI](https://www.videoproc.com/video-converting-software/buy.htm) | 转码、压缩、快速编辑与 AI 处理，功能远宽于切片但会被同一类用户比较 | **US$34.95/年**；**US$54.95** 终身；**US$79.95** 家庭终身 | 官方英文 Mac 购买页：年付支持 3 台 Mac/PC 并自动续订；终身版为 1 台，家庭版为 3–5 台。 |

## 结论

- 有直接竞品，而且 Mac App Store 的「单用途分割器」一次性买断主带为 **US$1.99–9.99**；功能更强的无损/帧准确工具则在 **US$18.99–29.99**。
- BiCut 当前功能最贴近 `Batch Video Splitter`（等时长切片，US$9.99），同时以本地、轻量、预览与导出透明度同 LosslessCut/SolveigMM 竞争。它尚未具备这些工具的手动多区间、全格式/字幕轨道或专有无损引擎广度。
- 若采用一次性买断，**US$7.99–12.99** 是与当前「等时长切片 + 本地原生体验」相称的首发试价区间：避开 US$1.99–3.99 的老工具低价带，也低于 LosslessCut 的 US$18.99 和 SolveigMM 的 US$29.99。若后续加入手动多区间、批量源文件、更多容器/轨道处理或稳定的帧准确保证，再测试 **US$14.99–19.99** 更合理。

## 价格口径与限制

- 除特别标注的剪映中国区外，App Store 价格均为**美国（US）Mac App Store**店面，以 USD 原样记录；App Store 会按国家/地区展示本地价格，税费、促销和最终结算价可能不同。
- 官网标价是当日网页显示的促销/公开价；VideoProc、TunesKit 和 CapCut 的订阅或促销价格可随地区、账号和活动变动。没有把它们换算为人民币，也没有把不同计费模式强行比较为同一价格。
- Bandicut 未纳入 macOS 比价：其[官方系统要求](https://www.bandicam.com/bandicut-video-cutter/support/)仅列 Windows，故不是 BiCut 的 Mac 直接竞品。
