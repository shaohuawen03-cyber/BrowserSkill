# 整合包：mattpocock/skills 精选（v2.0，2026-09-18）

来源：github.com/mattpocock/skills（265k star）。以下每个协议都经过适配，
落到本仓库的工作流（arena 派发 / git-sync 回路 / 本机验收）里。
原始概念版权归 mattpocock/skills（MIT），此处为改编整合并注明出处。

## 1. grilling / grill-me —— 派发前拷问（对应第 7 节协议）

原文：`skills/productivity/grilling/SKILL.md`（grill-me 是它的用户触发壳）。
核心：把未定决策画成**决策树**，每轮只问"前沿"（前提已落定的问题），
每题给推荐答案；事实自己去查（git/文件/网页），决策必须问用户；
前沿清空 = 共识达成，才允许行动。
适配：arena 任务令派发前跑 1-3 轮拷问（见 SKILL.md 第 7 节）。

## 2. handoff —— 交接文档纪律

原文：`skills/productivity/handoff/SKILL.md`。
核心：交接文档给"零上下文的新 agent"，引用产物用路径/URL 不复制内容，
脱敏（密钥/PII 用 <REDACTED>），附"suggested skills"清单，按下一程定制。
适配：git-sync 每轮的 `results/status/check_rN_*.txt` + handshake.json
就是交接文档 —— 自 v2.0 起遵循：**引用而不内联大产物、密码/token 一律
脱敏、每轮判定附"下一轮建议"三行**。

## 3. wait-what —— 复述确认（ASD-STE100 简明技术英语）

原文：`skills/productivity/wait-what/SKILL.md`。
核心："你上一条我没接住 —— 重新讲：先给一点上下文，用简明技术英语。"
适配：当用户出现"不对啊 / 你误解了 / 不是这个意思"时，立即触发：
① 一句话背景 ② 大白话复述我理解的任务 ③ 差异点列表让用户勾选。
**禁止**在未复述确认前继续执行。本仓库 2026-09-18 的三轮误会
（3 个会话 vs 3 轮）就是缺这一步。

## 4. to-spec —— 对话合成规格（不访谈）

原文：`skills/engineering/to-spec/SKILL.md`。
核心：不追问，直接把已有共识合成规格：问题陈述 / 方案 / 用户故事
（As an X, I want Y, so that Z）/ 验收清单。
适配：拷问轮结束后，把共识写成 `results/status/arena_promptN.txt`
前先落一份 `results/status/round_spec_N.md`（同构模板），任务令由
规格机械翻译而来 —— 任务令里不允许出现规格里没有的承诺。

## 5. diagnosing-bugs —— 反馈环第一定律

原文：`skills/engineering/diagnosing-bugs/SKILL.md`。
核心：硬 bug 的 90% 在"先造一个**紧的**红/绿信号"（失败测试 / 脚本 /
回放 / 二分 / 差分回路），其余是机械活。
适配：写入铁律表第 11 条 —— 排查桥接/浏览器问题**先造可重复的
红/绿信号**（本仓库实践：census 日志、housekeep 前后对比、
check_rN 的 exit code），禁止"改一版盲跑一轮"式的无信号迭代。

## 6. code-review —— 双轴验收

原文：`skills/engineering/code-review/SKILL.md`。
核心：对 diff 跑两轴 —— **Standards**（符不符合仓库成文规范）与
**Spec**（是否忠实实现规格），并行互不污染，结论并排呈现。
适配：本机验收 `local_check.ps1` 天然两轴：一致性门（ASCII/根目录
脚本同步 = Standards）+ 交付物判据（criteria = Spec）。v2.0 起判定
文件必须**分轴写结论**：`STANDARDS: pass/fail` 与 `SPEC: pass/fail`
分开陈述，混在一起的一律视为无效判定。

## 选用索引（其余 30+ 技能）

| 技能 | 一句话 | 何时用 |
|---|---|---|
| tdd | 红-绿-重构最小环 | 写钩子脚本逻辑时 |
| to-tickets | 规格拆工单 | 多会话并行排期 |
| wayfinder | 生代码库导航 | 接手陌生仓库 |
| triage | 工单分类 | 批量需求涌入 |
| domain-modeling | 领域建模 + ADR | 架构决策留档 |
| wizard | 向导式长流程 | 新人引导 |
| teach | 费曼教学 | 给用户讲机制 |
