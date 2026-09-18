# git-sync 技能装进 BrowserSkill 时的本地适配

安装时间：2026-09-18 · 技能版本 v2.9.2
来源：`https://github.com/shaohuawen03-cyber/new.git` 分支 `arena/01a0aeb9-new`（commit `dadc1c8950abb44b8df0d16a22a433fce8417854`）
目标：本仓库 `BrowserSkill`，分支 `arena/01a0b23a-browserskill`

## 1. `install.ps1` 命名冲突（已保护仓库自带文件）

BrowserSkill 根目录**本来就有** `install.ps1` —— 它是 bsk CLI 的 Windows 安装器，
README / AGENT_INSTALL.md 里的 `irm .../install.ps1 | iex` 就靠它。
git-sync 技能也有一个同名的 `install.ps1`（把技能装到别的仓库用）。

安装器 v2.9.2 的行为是**无条件覆盖**根目录同名文件，实测把 BrowserSkill 的安装器
覆盖掉了（`git status` 显示 `M install.ps1`）。已恢复原文件，并做两层保护：

* 根目录保留 BrowserSkill 自己的 `install.ps1`（内容与 `main` 一致，`md5=ff33756c9e661ef64a0bf588cb41a373`）；
* git-sync 的那份留在 `skills/git-sync/scripts/install.ps1`，用法：
  `.\skills\git-sync\scripts\install.ps1 -Target <别的仓库> -Branch <分支>`；
* `skills/git-sync/scripts/agent-install.sh` 已修：根目录同名 `.ps1` 若**已被 git 跟踪且内容不同**，
  打印 `KEPT: ... not overwritten` 并跳过，不再覆盖。

## 2. gate 作用域收敛（`code/check_all.sh`）

BrowserSkill 自带的两个 PowerShell 文件是**故意**含 UTF-8 字符（em dash）的：

* `./install.ps1`
* `./scripts/install-windows.test.ps1`

原版 gate 扫全仓库 `.ps1` 要求纯 ASCII，会因为这两个文件误判失败；原版第 3 项还要求
根目录 `install.ps1` 与技能副本逐字节相同，与第 1 条的保护直接冲突。所以：

* 第 1 项（ASCII）与第 4 项（PowerShell 解析）只扫 git-sync 自己的 `.ps1`
  （`is_gitsync_ps1()` 排除 `./install.ps1` 与 `./scripts/*`）；
* 第 3 项（根目录 vs 技能副本一致性）的清单去掉 `install`，其余 11 个脚本照旧逐个比对；
* `skills/git-sync/templates/check_all.sh` 同步成同一份，避免将来重装又拿回旧逻辑
  （`code/check_all.sh` 本身是"只建不覆盖"，升级不会丢）。

## 3. 上游 bug：`agent-install.sh --source <git-url>` 直接崩

`fetch_source()` 在 `set -u` 下引用未绑定的 `$3`，而 `--source <git-url>` 这条路径只传两个参数：

```
agent-install.sh: line 106: $3: unbound variable
[ERROR] clone failed: https://github.com/shaohuawen03-cyber/new.git (arena/01a0aeb9-new)
```

即 SKILL.md 第 7 节文档里那条一行命令，**只要带 `--source` 就必崩**（不带 `--source`
走候选探测分支、传三个参数，所以平时没暴露）。本仓库副本已修为 `dir="${3:-}"` + 兜底目录，
并在 `/tmp` 临时克隆上实测通过（能从 GitHub 正常拉取并完成安装）。
**建议把这两处修复合回技能总部分支 `arena/01a0ae7a-new`。**

## 4. 沙箱里没跑到的那一项

`code/check_all.sh` 第 4 项（用 PowerShell 自己的解析器检查每个 `.ps1` 语法）在本沙箱
**SKIP**：没有 `pwsh`/`powershell`，也无 root 装不了（`apt` 权限不足、
`release-assets.githubusercontent.com` 被出网策略拦截）。
其余 5 项全部 OK，gate 退出码 0。
这一项会在你 Windows 机器上真正执行 —— `code\local_check.ps1` 每轮都会跑同一个 gate，
那边有 PowerShell 5.1。
