# StealthReader — 隐秘小说阅读器

一个看起来像系统日志查看器的 macOS 本地 txt 小说阅读器。
深色终端风格界面，按一下 Esc 整屏变成持续滚动的仿真系统日志。

**给你用的成品：`~/Desktop/StealthReader.app`**（独立完整，拷到哪都能跑）
**发给朋友：`~/Desktop/StealthReader.zip`**（微信/网盘传这个，别直接发 .app）

## 功能

- **打开本地 txt**：UTF-8 / GBK（GB18030）/ UTF-16 自动识别，LF / CR / CRLF 换行通吃
- **大文件秒开**：7MB 约 0.2 秒、16MB GBK 约 0.7 秒；分页渲染，翻页零卡顿
- **章节目录**：自动识别「第X章/卷/回」「Chapter N」「楔子/番外」等；⌘\\ 呼出侧边栏，⌘F 筛选，点击跳转；识别不出章节时按 500 行分块
- **隐秘伪装**：
  - **Esc 老板键**：整屏切换为滚动的仿真 macOS 日志（真实主机名、真实进程名），再按 Esc 回到原页面
  - **切走自动伪装**：切换到其他应用时自动变假日志（显示 → 切走时自动暂停 可关闭）
  - **关窗即伪装**：关掉窗口后再从 Dock 打开，看到的先是日志画面
  - 伪装期间除 Esc 外所有按键被吞掉，目录侧边栏自动隐藏，防止穿帮
- **进度记忆**：按「文件路径 + 大小 + 修改时间」记忆，重开回到上次位置；文件更新过则从头开始
- **通用二进制**：Apple 芯片（arm64）和 Intel（x86_64）Mac 都能直接运行

## 使用方式

1. 双击打开，首次会请求访问「下载/桌面/文稿」文件夹 —— 点「允许」（macOS 隐私保护，所有 App 都要）
2. 把 txt 拖进窗口、按 ⌘O 选择、或在 txt 上右键「打开方式 → StealthReader」

## 快捷键

| 按键 | 功能 |
|---|---|
| `␣` / `→` / `↓` / `PageDown` | 下一页 |
| `←` / `↑` / `PageUp` | 上一页 |
| `Home` / `End` | 开头 / 结尾 |
| `⌘\\` | 显示 / 隐藏章节目录 |
| `⌘F` | 筛选章节（输入关键字） |
| `Esc` | 老板键：阅读 ⇄ 假日志 |
| `⌘O` | 打开文件 |
| `⌘+` / `⌘-` | 放大 / 缩小字号 |
| `⌘Q` / `⌘W` | 退出 / 关窗（关窗后点 Dock 图标重开） |

滚轮轻扫翻页。老板键无论焦点在正文、目录还是搜索框都有效。

## 发给朋友

1. 发 `StealthReader.zip`（448KB，通用二进制，Intel / Apple 芯片通吃）
2. 朋友解压后把 StealthReader.app 拖到「应用程序」或任意位置
3. 首次打开若提示「无法验证开发者」：
   - macOS 13 及以前：右键 App →「打开」→「打开」
   - macOS 14+：先双击运行一次（被拦）→ 系统设置 → 隐私与安全性 → 点「仍要打开」
   - 这是因为 App 未做公证（需要付费开发者账号）；本地使用功能完全不受影响
4. 首次打开小说文件时会弹「访问下载文件夹」权限，点「允许」

## 从源码构建

```bash
cd stealth-reader
./build.sh        # 产出 StealthReader.app（通用二进制）
swift gen_icon.swift && iconutil -c icns ConsoleIcon.iconset -o ConsoleIcon.icns   # 重新生成图标（可选）
```

需要 Xcode Command Line Tools。`build.sh` 顶部可改 `APP_NAME` / `BUNDLE_NAME`。

## 数据存放位置

阅读进度与最近列表：`~/Library/Preferences/com.stealthreader.app.plist`（系统标准偏好存储，无其他残留）。
