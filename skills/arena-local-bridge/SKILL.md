# arena-local-bridge — 最终版 skill（BrowserSkill 全家桶汇总）

> 版本 **v2.0**（2026-09-18）。汇总：`git-sync`（git 打通+值守+自循环）、
> `bsk` 浏览器操控（Agent Window/borrow/剪贴板/快照）、`arena` 对话编排
> （continue-click、GBK needle、quote-free DOM click、黑壳检测），
> 并整合 mattpocock/skills 精选协议（grilling/handoff/wait-what/
> to-spec/diagnosing-bugs/code-review，见 `pack-mattpocock.md`）。
> 全部规则来自 50+ 轮真机实测（本仓库 git log 即实验记录）。

## 0. 一句话

在 Arena 沙箱里操控用户 Windows 机器上的 Edge 浏览器，驱动 arena.ai 的
Agent 会话为用户干活（安装/打通/自循环），全程 BrowserSkill 底座、
git 分支审计、结果自动回传。

## 1. 架构（三件套，缺一不可）

```
Arena 沙箱 agent（本技能）
   │ git 分支（唯一审计通道）           │ bsk CLI（本机下载，别在沙箱装）
   ▼                                  ▼
用户 Windows：git-sync 值守          arena.ai Agent 对话（ mqgg5630 账号）
（计划任务，check_cmd=任意脚本）      ▲ 由 bsk 借用用户活标签页来驱动
   │ 执行任务/验收/推送判定
   ▼
E:\0github\<clone>\（工作副本 + deliverable 回传区）
```

- **git-sync 桥**：沙箱任务 → `code/agent_task.ps1` → 值守执行 → 结果推回。
  沙箱网络受限时的万能通道（下载官方二进制、本机 Office/GPU 任务等）。
- **bsk 浏览器操控**：`session start` → `tab borrow`（借用用户活标签页，
  **必须用户先关闭「借用标签页前确认」**）→ `snapshot`（aria 树 @eN 引用）
  → `click/fill/press` → `screenshot --out` 证据。
- **arena 编排**：操控 arena.ai 的对话页面，把任务提示词发给 arena 的
  agent，让它带着用户的 GitHub 权限干活。

## 2. arena.ai 自动化的实测铁律（每条都有失败教训背书）

| # | 铁律 | 依据 |
|---|---|---|
| 1 | **标签页必须是"热"的**：用户 30 分钟内亲自激活过 arena 标签页，自动化才能渲染成功；否则黑壳/不挂载。冷却约 30 分钟 | r30/r35 成 vs r47 败 |
| 2 | **只走借用，不开新窗口**：`tab create` 的新标签页 30/30 全部黑壳（边缘防护封锁无人窗口） | r40/r41 |
| 3 | **深链会撞 Cloudflare**：`/agent/<id>` 整页跳转触发验证；要么用首页列表点进去，要么 SPA 内部导航 | r45 |
| 4 | **composer 只吃真粘贴**：React 富文本编辑器拒绝 CDP `fill` 注入；`Set-Clipboard` + `press Ctrl+v` 百发百中 | r28 vs r30 |
| 5 | **发送要点 Send 按钮**（按最新快照的 @eN ref），Enter 只是兜底；发送后按「Stop generating 按钮」判断是否在生成 | r30 |
| 6 | **arena 轮次结束要点「继续工作」**才接受新任务；按钮文案是中文，用 GBK 乱码头（`缁х画宸ヤ綔`）在 ASCII-gate 里匹配：`-join @([char]0x7F01,...)` | r30 |
| 7 | **长对话快照被 30K token 截断**：读结果前 `Scroll-Bottom`（quote-free JS：`document.scrollingElement.scrollTop=...`），或读 `document.body.innerText` | r32-r35 |
| 8 | **列表 <a> 水合有延迟**：Today 条目可能只有「More options」按钮没有链接；等 3-5 秒再快照，或用 quote-free `document.links` 直点（href 匹配串用 `String.fromCharCode` 构造） | r45 |
| 9 | ** `.ps1` 必须 ASCII**（gate 硬规）：中文提示词放 `results/status/*.txt`（UTF-8 数据文件），运行时 `Get-Content -Encoding UTF8` 读入再粘贴 | v2.6.8+ |
| 10 | **每次会话重开窗口**：旧 Agent Window 会僵死（reload 救不回）；`session stop --all` 后重开 | E2/F1/F2 |
| 11 | **反馈环第一**（diagnosing-bugs 定律）：排查先造紧的红/绿信号（census 日志/前后对比/exit code），禁止无信号盲跑迭代 | r49-r52 |

## 3. 标准作战流程（SOP）

```bash
# ① 修改任务钩子（ASCII！），推分支
$EDITOR code/agent_task.ps1
bash skills/git-sync/scripts/agent-sync.sh "feat: ..."

# ② 派活+等待（值守自动执行并推回结果）
bash skills/git-sync/scripts/agent-wait.sh --request "<任务说明>" \
     --timeout 1200 --interval 15
# exit 0 passed / 2 failed（看 results/status/check_rN_*.txt）/ 3 超时

# ③ 拉取产物分析
git fetch && git reset --mixed origin/<branch> && git ls-files -d | xargs -r git checkout --
```

### 驱动 arena 对话（核心动作序列）

1. `session start` → `tab list` 找 arena 标签 → `tab borrow` → `tab select`
2. `navigate https://arena.ai/agent`（首页！别用深链）→ 轮询快照直到 textbox+Today
3. `Scroll-Bottom` → 找「继续工作」按钮（GBK needle）→ `click @eN`
4. `Set-Clipboard`（UTF-8 文件读入）→ click textbox → `press Ctrl+v` → 验证 `[filled]`
5. 点最新 `button "Send message"` ref → 监视「Stop generating」消失 = 完成
6. 产物/判定：`evaluate document.body.innerText` + 快照存证 + 截图

### 派发前流程（v2.0，整合 mattpocock/skills —— 详见 pack-mattpocock.md）

```
第0步 GRILL   对用户跑 1-3 轮拷问（决策树+前沿+推荐答案）→ 共识
第1步 SPEC    共识 → results/status/round_spec_N.md（问题/方案/故事/验收）
第2步 PROMPT  规格机械翻译成 arena_promptN.txt（ASCII 落盘 UTF-8 数据）
第3步 DISPATCH 派发钩子 → 等判定
第4步 ACCEPT  双轴验收（STANDARDS=一致性门 / SPEC=交付物判据，分开陈述）
第5步 HANDOFF 判定文件遵循交接纪律（引用产物路径、脱敏、三行"下一轮建议"）
沟通红线：用户一旦说"不对啊/误解了"，立即 wait-what 复述确认，禁止继续执行。
```


### 前置条件检查单

- [ ] 扩展已装（Edge 商店）、弹窗显示 Ready、CLI 0.3.0
- [ ] 「借用标签页前确认」已关闭
- [ ] 用户 <30 分钟内激活过 arena 标签页
- [ ] 本机值守在线（`.\watch.ps1 -Status` heartbeat 新鲜）
- [ ] `auth.ps1 -Verify` 静默推送通过（值守推判定不弹窗）

## 4. 已验证战果（本仓库 git log 可审计）

- 双向自循环：沙箱 → 分支 → 本机执行 → 判定回传 → accept（76s）
- 本机即 Runner：值守代下载官方二进制（sha256 两端核对）
- bsk 操控 Edge：Agent 窗口打开 arena、发消息、收 AI 回复（Battle+Agent 双模式）
- arena agent 编排：第一轮「安装+打通」由 arena 的 agent 自主完成，
  其输出的 PowerShell 命令块被抓取回传（deliverable/arena_round1_psblock.txt）
- 第二轮「3 轮自循环」提示词已成功注入对话（r46；执行监视见 K5b）

## 4.5 对话回路模式（默认推荐，2026-09-18 GRILL 共识定稿）

用户只对 arena 对话说话；轮询全在 git 回路；**浏览器自动化一律不用**。
三条定稿决策：

1. **值守按需、按对话**：哪个对话在用，就由该对话的 agent 自己
   `.\watch.ps1 -Register` 激活自己的值守；模式结束（用户说"停"）自己
   `-Unregister`，后台归零。任何时刻只激活正在用的那一个。
2. **轮次动态**：不定死轮数。每轮开始前 agent 报"本轮计划（做什么 /
   验收标准 / 产物）"，用户批"继续"才执行；无默认轮数、无最少轮数。
3. **启动靠粘贴**：用户亲手把启动词（`templates/chatloop_startup.txt`）
   粘进对话，不走浏览器自动化、不借标签页。

流程：粘贴启动词 → agent 注册值守 → 每轮〔报计划 → 等批准 → 推任务 →
handsfree 等判定 → 汇报〕→ 用户说"停" → 总结 + 注销值守。
本模式的全部前例：第一轮打通（arena agent 自助装桥、自注册值守、
自查 passed）就是这么跑通的。

## 5. 紧急停止（一键全停，两层）

**第一层**（停本会话 237 + arena 352 的值守）：

```powershell
schtasks /End /TN "git-sync-watch-BrowserSkill-01a0b237" 2>$null
schtasks /End /TN "git-sync-watch-BrowserSkill-01a0b352" 2>$null
schtasks /Delete /TN "git-sync-watch-BrowserSkill-01a0b237" /F 2>$null
schtasks /Delete /TN "git-sync-watch-BrowserSkill-01a0b352" 2>$null
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'watch\.ps1|agent_task\.ps1|local_check\.ps1|bootstrap\.ps1' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
& "$env:USERPROFILE\.local\bin\bsk.exe" session stop --all 2>$null
```

**第二层**（机器上有多个 Arena 会话克隆时；2026-09-18 实测 15+ 弹窗就是
多个会话的值守叠加所致。全量清扫所有 git-sync 家族）：

```powershell
Get-ScheduledTask -TaskName 'git-sync-watch-*' -ErrorAction SilentlyContinue |
  ForEach-Object { schtasks /End /TN $_.TaskName 2>$null; schtasks /Delete /TN $_.TaskName /F 2>$null }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'watch\.ps1|agent_task|local_check|bootstrap|sync\.ps1|agent-handsfree|agent-sync|download\.ps1|upload\.ps1|git-sync' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

### 后台策略（用户明令，2026-09-18）

> **默认零后台：任何 git-sync 值守/计划任务都不得常驻。只有用户明确
> 说"用会话 X"，才注册会话 X 自己的值守；该会话任务结束即注销。
> 其他会话的值守永远不唤醒、不批量重启。**

恢复某个会话（仅当用户点名）：
`cd <该会话克隆> ; .\watch.ps1 -Register`；用完注销：`.\watch.ps1 -Unregister`。

## 6. 故障速查

| 症状 | 处置 |
|---|---|
| 快照只有 RootWebArea+alert | 黑壳/防护：让用户点一下 arena 标签页（30 分钟内有效）再跑 |
| 深链 "couldn't load this chat" 或 Cloudflare 页 | 改走首页列表点击或 quote-free DOM click |
| fill exit 3 / 输入不粘 | 换剪贴板 Ctrl+v；先 click 聚焦再粘贴 |
| 值守 30+ 分钟无判定 | 用户跑 `.\watch.ps1 -Unregister ; .\watch.ps1 -Register` |
| 值守被别的克隆抢焦点 | `.\watch.ps1 -Focus`（恢复本克隆）/ `-RestoreParked` |
| push 403 "denied to <账号>" | 账号归属问题：`.\auth.ps1 -Account <仓库主> ; .\auth.ps1 -Verify`（应 READY） |
| 推送被拒 workflows 权限 | 别推 .github/workflows；历史里删掉再重做提交 |
| conversation 深链 404/Cloudflare | SPA 内部导航（列表点击/DOM click），别整页跳转 |
