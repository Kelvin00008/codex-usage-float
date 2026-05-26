# Publishing Guide

## English

Suggested repository name:

```text
codex-usage-float
```

Suggested repository description:

```text
A tiny macOS floating widget that shows Codex usage remaining in real time.
```

Suggested topics:

```text
codex, macos, swift, appkit, usage-widget, floating-window
```

### Publish With GitHub CLI

```bash
gh auth login
gh repo create codex-usage-float --public --source=. --remote=origin --push
```

### Publish Manually

1. Create a new GitHub repository named `codex-usage-float`.
2. Copy the repository URL.
3. Run:

```bash
git remote add origin YOUR_REPOSITORY_URL
git push -u origin main
```

### Release Package

The source package is generated at:

```text
release/codex-usage-float-source.zip
```

Upload it to a GitHub Release if you want people to download the source directly.

---

## 中文

建议仓库名：

```text
codex-usage-float
```

建议仓库简介：

```text
一个用于实时显示 Codex 剩余用量的 macOS 桌面浮窗。
```

建议标签：

```text
codex, macos, swift, appkit, usage-widget, floating-window
```

### 使用 GitHub CLI 发布

```bash
gh auth login
gh repo create codex-usage-float --public --source=. --remote=origin --push
```

### 手动发布

1. 在 GitHub 新建一个名为 `codex-usage-float` 的仓库。
2. 复制仓库地址。
3. 运行：

```bash
git remote add origin YOUR_REPOSITORY_URL
git push -u origin main
```

### 发布包

源码包已生成在：

```text
release/codex-usage-float-source.zip
```

如果你希望别人直接下载源码，可以把这个 zip 上传到 GitHub Release。
