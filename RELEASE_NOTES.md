# Release Notes

## v0.3.1

English:

- Renders the menu bar badge as a white image so the percentage stays visible on macOS menu bar backgrounds.
- Stabilizes the popover layout with centered rows and fixed-width progress bars.
- Adds icon-only popover controls for refresh, restart, and quit.
- Uses a steadier stdio app-server read path to avoid intermittent `Unavailable` states.
- Updates README with the latest menu bar screenshot and bilingual benefit summary.

中文：

- 将状态栏徽标渲染为白色图片，避免百分比被 macOS 显示成黑色。
- 固定弹窗居中布局和进度条宽度，减少刷新时的跳动。
- 在弹窗底部新增仅图标显示的刷新、重启、退出按钮。
- 改用更稳定的 stdio 读取方式，减少偶发 `Unavailable` 状态。
- 更新 README 截图和中英双语优点说明。

## v0.3.0

English:

- Moves the UI into the macOS menu bar.
- Refreshes usage on hover and shows a compact translucent popover.
- Removes the always-on-top desktop panel behavior from the main experience.

中文：

- 将组件改为 macOS 状态栏显示。
- 鼠标移上去时自动刷新用量，并显示紧凑的毛玻璃弹窗。
- 主体验不再使用桌面常驻浮窗。

## v0.2.0

English:

- Fixes usage refresh after the Codex 0.133 app-server update.
- Uses the newer app-server proxy/daemon path first, with a legacy stdio fallback.
- Handles the newer multi-bucket `rateLimitsByLimitId` response and prefers the `codex` bucket.
- Adds a Finder-friendly `Install Auto-Start.command` launcher.
- Updates LaunchAgent installation to use the modern `launchctl bootstrap` flow.

中文：

- 修复 Codex 0.133 更新后用量刷新失效的问题。
- 优先使用新版 app-server proxy/daemon 连接方式，并保留旧版 stdio 回退。
- 兼容新版多桶 `rateLimitsByLimitId` 返回结构，并优先显示 `codex` 用量桶。
- 新增可在 Finder 里双击运行的 `Install Auto-Start.command` 安装入口。
- 自动启动安装改为使用较新的 `launchctl bootstrap` 流程。

## v0.1.0

English:

- Initial release of Codex Usage Float.
- Adds a translucent macOS floating widget for Codex usage limits.
- Reads `account/rateLimits/read` from the local Codex app-server.
- Shows short-window and weekly-window remaining percentages and reset times.
- Supports resizing, refresh button, close button, and optional Codex-aware auto-start.

中文：

- Codex Usage Float 初始版本。
- 新增 macOS 半透明桌面浮窗，用于显示 Codex 用量限制。
- 通过本地 Codex app-server 读取 `account/rateLimits/read`。
- 显示短周期窗口与周窗口的剩余百分比和重置时间。
- 支持调整尺寸、手动刷新、关闭按钮，以及可选的 Codex 跟随启动。
