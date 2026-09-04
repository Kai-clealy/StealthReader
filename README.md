# StealthReader

A local txt novel reader for macOS that disguises itself as a system log viewer.
Dark terminal-style UI; one press of `Esc` switches the entire window into an endlessly scrolling, realistic fake system log.

**For your own use: `~/Desktop/StealthReader.app`** (fully self-contained — run it from anywhere)
**To share with friends: `~/Desktop/StealthReader.zip`** (send the zip, not the raw .app)

## Features

- **Open local txt files**: auto-detects UTF-8 / GBK (GB18030) / UTF-16; handles LF, CR and CRLF line endings
- **Instant open for huge files**: 7 MB in ~0.2 s, 16 MB GBK in ~0.7 s; page-based rendering, zero-lag paging
- **Chapter sidebar**: recognizes「第X章/卷/回」(Chinese chapter headings), `Chapter N`, prologues/epilogues; ⌘\ to toggle, ⌘F to filter, click to jump; falls back to 500-line chunks when no chapters are found
- **Stealth disguise**:
  - **Esc boss key**: swaps the whole window for a scrolling fake macOS log (real hostname, real process names); press Esc again to return exactly where you were
  - **Auto-disguise on switch-away**: switching to another app instantly shows the fake log (toggle in Display menu)
  - **Disguise on window close**: reopening from the Dock always shows the log view first
  - While disguised, every key except Esc is swallowed and the sidebar hides itself — no accidental exposure
- **Reading progress**: remembered per file (path + size + mtime); reopening resumes where you left off; updated files start fresh
- **Universal binary**: runs natively on both Apple silicon (arm64) and Intel (x86_64) Macs

## Usage

1. Launch the app; on first run macOS asks for access to your Downloads/Desktop/Documents folder — click **Allow** (standard privacy protection)
2. Drag a txt into the window, press ⌘O, or right-click any txt → Open With → StealthReader

## Keyboard Shortcuts

| Key | Action |
|---|---|
| `Space` / `→` / `↓` / `PageDown` | Next page |
| `←` / `↑` / `PageUp` | Previous page |
| `Home` / `End` | Beginning / end |
| `⌘\` | Toggle chapter sidebar |
| `⌘F` | Filter chapters |
| `Esc` | Boss key: reading ⇄ fake log |
| `⌘O` | Open file |
| `⌘+` / `⌘-` | Bigger / smaller font |
| `⌘Q` / `⌘W` | Quit / close window (click the Dock icon to reopen) |

Mouse-wheel swipe pages. The boss key works no matter whether focus is on the text, the sidebar, or the search field.

## Sharing with Friends

1. Send `StealthReader.zip` (448 KB, universal binary)
2. Unzip, drag StealthReader.app into Applications (or anywhere)
3. First launch may warn "cannot verify the developer" (unsigned, no paid notarization):
   - macOS 13 or earlier: right-click the app → Open → Open
   - macOS 14+: double-click once (gets blocked) → System Settings → Privacy & Security → Open Anyway
4. First time opening a novel, allow folder access when prompted

## Building from Source

```bash
./build.sh        # produces StealthReader.app (universal binary)
swift gen_icon.swift && iconutil -c icns ConsoleIcon.iconset -o ConsoleIcon.icns   # regenerate icon (optional)
```

Requires Xcode Command Line Tools. Edit `APP_NAME` / `BUNDLE_NAME` at the top of `build.sh` to change the disguise name.

## Data Storage

Reading progress and recents live in `~/Library/Preferences/com.stealthreader.app.plist` (standard preferences; nothing else is written to disk).

---

# StealthReader（中文说明）

一个伪装成系统日志查看器的 macOS 本地 txt 小说阅读器。
深色终端风格界面，按一下 `Esc` 整屏变成持续滚动的仿真系统日志。

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
./build.sh        # 产出 StealthReader.app（通用二进制）
swift gen_icon.swift && iconutil -c icns ConsoleIcon.iconset -o ConsoleIcon.icns   # 重新生成图标（可选）
```

需要 Xcode Command Line Tools。`build.sh` 顶部可改 `APP_NAME` / `BUNDLE_NAME`。

## 数据存放位置

阅读进度与最近列表：`~/Library/Preferences/com.stealthreader.app.plist`（系统标准偏好存储，无其他残留）。
