# BrowserSkill 技能总目录（SKILLS.md）

> 本文件是本分支全部技能的**唯一总目录**。索引区段由
> `skills/gen_skills_index.sh` 自动生成，**每次 agent-sync 推送都会刷新**；
> 任何仓库通过 `install.ps1 / agent-install.sh` 安装本分支技能时，
> 本文件会一并复制过去。手写内容在标记区之外，机器只改标记之间。

## 1. 这个仓库是什么

**BrowserSkill** = 让沙箱里的 AI agent 安全操控用户 Windows 机器的三件套：

```
Arena 沙箱 agent
   │  ① git-sync 桥（分支=审计通道，值守=本机执行器）
   │  ② bsk 浏览器桥（借用用户 Edge 的活标签页，Agent Window 沙箱）
   ▼
用户 Windows 机器：执行任务 / 驱动 arena.ai 会话 / 回传产物与判定
```

设计原则：**每一步可审计**（git 提交即证据）、**默认零后台**（值守按需
注册、用完注销）、**窗口零残留**（自动化会话首尾都 `session stop`）。

## 2. 技能目录（自动生成，勿手改）

<!-- BEGIN:AUTO-INDEX -->
| 技能 | 版本 | 说明 |
|---|---|---|
| **arena-local-bridge** | 2.0 | arena-local-bridge — 最终版 skill（BrowserSkill 全家桶汇总） — 版本 v2.0（2026-09-18）。汇总：`git-sync`（git 打通+值守+自循环）、 |
| **git-sync** | 2.9.2 | git-local-arena-sync — TRIGGER: user says 安装https://arena.ai/agent/01a0a821 的skills 与本地打通 (or 安装 arena/01a0a821-git-pull-arena skills). Do NOT open arena.ai (login… |
<!-- END:AUTO-INDEX -->

## 3. git-sync（v2.9.2）—— 沙箱↔本机双向桥

一句话：任务进分支 → 本机值守拉取执行 → 判定推回 → 沙箱验收收尾。

### 脚本全家桶（skills/git-sync/scripts/）

| 脚本 | 方向 | 用途 |
|---|---|---|
| `sync.ps1` | 本机←远端 | 拉取沙箱推上来的任务/产物 |
| `push.ps1` | 本机→远端 | 提交+推送本机产物 |
| `watch.ps1` | 常驻(按需) | 值守循环；`-Register/-Unregister/-Status/-RestoreParked` |
| `bootstrap.ps1` | 本机 | 首次安装入口（`-Auto`）；注意单值守停车规则 |
| `local_check.ps1` | 本机 | 一致性门（ASCII/根目录脚本同步/语法/判据） |
| `agent_task.ps1` | 沙箱写/本机跑 | 每轮任务钩子（干活的地方） |
| `download.ps1` | 远端→本机目录 | 产物下载；跑完打印来源仓库/分支/提交/目标目录 |
| `where.ps1` / `where.cmd` | 本机 | `.\where.cmd -Want <分支>` 直接标出该用哪份克隆 |
| `auth.ps1` | 本机 | 多账号钉扎 + 静默推送验证（`-Verify`） |
| `doctor.ps1` | 本机 | 诊断+修复建议 |
| `install.ps1` | 本机 | 把用户侧脚本+gate 装进目标仓库根目录 |
| `agent-sync.sh` | 沙箱 | 提交+推送+门禁+回执（**推送前自动刷新本文件索引**） |
| `agent-wait.sh` | 沙箱 | 派活+等判定（`--request`，exit 0/2/3） |
| `agent-check.sh` | 沙箱 | `--accept` 收尾闭环 |
| `agent-handsfree.sh` | 沙箱 | 全自动：派活→等→验收→收尾 |
| `agent-install.sh` | 本机 | 从源仓库装最新版 git-sync |

### 生命周期（用户政策，2026-09-18 起）

**默认零后台**。只有用户点名"用会话 X"，才 `.\watch.ps1 -Register` X 的
值守；X 的任务结束立即 `-Unregister`。永不批量重启、永不唤醒其他会话。

### 判定协议（双轴，v2.0 起）

本机验收必须分轴陈述：`STANDARDS`（一致性门）与 `SPEC`（交付物判据）
分开写 pass/fail；判定文件 `results/status/check_rN_*.txt` 遵循交接纪律
（引用产物路径、脱敏、附三行"下一轮建议"）。

## 4. arena-local-bridge（v2.0）—— arena 会话编排 + 精选协议整合

详见 `skills/arena-local-bridge/SKILL.md` 与 `skills/arena-local-bridge/pack-mattpocock.md`。
要点：

- **11 条实测铁律**：热标签页(30min)、禁新窗口、禁深链、剪贴板真粘贴、
  Send 按钮、GBK 续工按钮 needle、Scroll-Bottom、DOM 免引号点击、
  .ps1 必须 ASCII、会话首尾收窗、反馈环第一。
- **派发前流程**：GRILL 拷问（决策树+前沿+推荐答案）→ SPEC 规格落盘 →
  PROMPT 机械翻译 → DISPATCH → 双轴 ACCEPT → HANDOFF。
- **整合 mattpocock/skills**：grilling / handoff / wait-what / to-spec /
  diagnosing-bugs / code-review（原文见 pack 文档出处表）。
- **紧急停止两层**（用户可随时一键全停，见其 SKILL.md 第 5 节）。
- **对话回路模式（默认推荐）**：用户只对 arena 对话说话，agent 自管
  值守（按需注册/注销）、每轮报计划等批准、动态轮次；启动词模板
  `skills/arena-local-bridge/templates/chatloop_startup.txt`，用户粘贴即用。

## 5. 安装与日常使用

### 安装本分支技能到新会话/新仓库

```powershell
# 方式一：整仓克隆后装用户侧脚本
git clone -b <分支> https://github.com/shaohuawen03-cyber/BrowserSkill.git E:\0github\<目录>
cd E:\0github\<目录>
powershell -NoProfile -ExecutionPolicy Bypass -File skills\git-sync\scripts\install.ps1
# 方式二（沙箱/agent）：bash skills/git-sync/scripts/agent-install.sh
```

`install.ps1` 会在目标仓库根目录放置：sync/push/download/**where**/watch/
auth/doctor/… + gate 脚本 + **本文件（SKILLS.md）**。

### 日常三件套 + 紧急停止

```powershell
.\sync.ps1                      # 拉最新
.\where.cmd -Want <分支或会话id> # 我该用哪个文件夹（[USE] 标记）
.\download.ps1 -Set final       # 产物落地（打印来源仓库/分支/提交/目录）
```

紧急停止（两层：单会话 / 全量清扫）见 `skills/arena-local-bridge/SKILL.md` 第 5 节。

## 6. 里程碑（git log 可审计）

| 日期 | 成果 |
|---|---|
| 09-18 上午 | arena agent 第一轮自管打通：装 git-sync v2.9.2、自建值守、自查 passed |
| 09-18 | where.cmd 文件夹定位 + download 来源打印 + docs 第零节（用户实测通过） |
| 09-18 | r46：剪贴板路线把 3 轮自循环任务令成功注入连接对话（composer [filled] + Send） |
| 09-18 | 15+ 弹窗事故复盘 → 零后台政策 + 两层紧急停止 + 窗口普查工具 |
| 09-18 | v2.0：整合 mattpocock/skills 六协议（grill/spec/handoff/wait-what/两轴/反馈环） |
| 09-18 | **对话回路模式定稿**（GRILL 共识）：用户只对话、git 回路自动轮询、按需值守、动态轮次、粘贴启动 |

## 7. 维护说明

- 索引区段（第 2 节标记之间）由 `agent-sync.sh` 第 4.5 步自动刷新；
  新增 `skills/<name>/SKILL.md` 即自动进表，无需手改本文件。
- 改本文件的手写区段随意；**不要动 `<!-- BEGIN:AUTO-INDEX -->` 标记**。
- 技能版本以各自 `VERSION` / SKILL.md 头部为准（git-sync: 2.9.2）。
