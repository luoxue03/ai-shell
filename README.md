# AI Shell

在任意终端中使用 `# <自然语言>` 生成 shell 命令。

基于 Kaku 终端的 AI 命令生成功能迁移而来，脱离了 WezTerm 引擎依赖，可在任意终端的 zsh 中运行。

## 效果

```
❯ # 查看当前目录最大的文件

   AI thinking...

  ╭─ AI Shell ───────────────────────────────────╮
  │ [1] 按文件大小排序列出当前目录
  │     ls -lS | head -n 2
  │     按文件大小排序并显示最大的一个文件
  │
  │ [2] 递归查找最大文件
  │     find . -type f -exec du -h {} + | sort -hr | head -n 1
  │     递归计算所有文件大小，取最大者
  ╰──────────────────── 按数字键选择，其他键取消 ─╯
```

按数字键选择方案，命令自动填入输入行，确认后回车执行。

## 特性

- **自然语言生成命令** — 输入 `# <描述>` 按回车
- **双方案选择** — 每次生成 2 个命令选项（从简单到进阶），一次 API 请求
- **中文说明** — summary 和 why 均为中文
- **危险命令检测** — `rm -rf`、`mkfs`、`dd`、`shutdown` 等自动标黄警告
- **命令净化** — 自动去除 markdown 代码块、`$ ` 前缀等
- **Kaku 兼容** — 在 Kaku 终端内自动禁用，避免与内置功能冲突
- **运行时开关** — `ai-shell off` 切换到 Kaku 内置，`ai-shell on` 切回
- **零依赖安装** — 仅需 zsh + curl + jq

## 安装

### 1. 确认依赖

```bash
# macOS 自带 curl 和 zsh，只需确认 jq
brew install jq
```

### 2. 配置 API

如果已安装 Kaku 终端并配置了 `~/.config/kaku/assistant.toml`，ai-shell 会自动读取，无需额外配置。

否则编辑 `~/.config/ai-shell/config`：

```bash
AI_SHELL_API_KEY="your-api-key"
AI_SHELL_MODEL="gpt-4o"
AI_SHELL_BASE_URL="https://api.openai.com/v1"
AI_SHELL_TIMEOUT=15
```

支持任何兼容 OpenAI chat/completions 接口的 API。

### 3. 加载插件

在 `~/.zshrc` 末尾添加：

```bash
# 仅启用 ai-shell（# 由 ai-shell 处理，Kaku 内置的 # 仍可在 ai-shell off 时使用）
[[ -f "$HOME/.config/ai-shell/ai-shell.zsh" ]] && source "$HOME/.config/ai-shell/ai-shell.zsh"
```

如果你**不想用 Kaku 内置的 `#` AI 功能**（即 `ai-shell off` 时让 `#` 当作普通注释），额外加载：

```bash
# 可选：先禁用 Kaku 的 # 功能，再加载 ai-shell
[[ -f "$HOME/.config/ai-shell/disable-kaku-ai.zsh" ]] && source "$HOME/.config/ai-shell/disable-kaku-ai.zsh"
[[ -f "$HOME/.config/ai-shell/ai-shell.zsh" ]] && source "$HOME/.config/ai-shell/ai-shell.zsh"
```

> `disable-kaku-ai.zsh` 在非 Kaku 终端中是 no-op，可以安全保留。

新开终端 tab 生效。

## 配置优先级

```
~/.config/ai-shell/config  >  ~/.config/kaku/assistant.toml  >  环境变量
```

## 使用

```bash
# 查看磁盘占用最大的目录
# 查找最近修改的 yaml 文件
# 统计当前 git 仓库的代码行数
# 批量重命名 .txt 为 .md
```

输入以 `#` 开头的描述，按回车即可。按数字键选择方案，其他键取消。

## 开关命令

在终端中直接运行 `ai-shell` 命令切换：

```bash
ai-shell off     # 禁用 ai-shell（# 回退到 Kaku 或注释，取决于是否加载 disable-kaku-ai.zsh）
ai-shell on      # 重新启用 ai-shell
ai-shell toggle  # 切换开关
ai-shell status  # 查看当前状态
```

开关状态会持久化到 `~/.config/ai-shell/state`，新终端 tab 自动继承。

`off` 后 `#` 的行为：
- 若加载了 `disable-kaku-ai.zsh` → 视为普通注释（zsh `.accept-line`）
- 否则 → 由 Kaku 内置 AI 处理

也可以在 sourcing 前设置环境变量永久禁用：

```bash
export AI_SHELL_DISABLE=1
```

## 上下文信息

每次请求自动附带：
- 当前工作目录 (`$PWD`)
- 当前 git 分支（如在 git 仓库中）

## 安全机制

以下命令会被标记为危险（黄色警告），但仍会填入输入行供确认：

| 模式 | 说明 |
|------|------|
| `rm -rf` / `rm -fr` | 递归强制删除（含 sudo） |
| `mkfs` | 格式化磁盘 |
| `dd if=` | 裸磁盘写入 |
| `shutdown` / `reboot` / `poweroff` | 系统关机重启 |
| `git reset --hard` | Git 硬重置 |
| `git clean -fd` | Git 强制清理 |
| fork bomb | 系统炸弹 |

## 文件结构

```
~/.config/ai-shell/
├── ai-shell.zsh         # 主插件（# AI 命令生成 + 开关）
├── disable-kaku-ai.zsh  # 可选：禁用 Kaku 内置的 # AI 功能
├── config                # API 配置（可选）
├── state                 # 开关状态（自动生成）
└── README.md             # 本文件
```

## 致谢

核心逻辑参考自 [Kaku Terminal](https://github.com/tw93/Kaku) 的 AI 命令生成实现。
