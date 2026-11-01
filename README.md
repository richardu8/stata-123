# stata-uni-bi-multi：用 Stata 做单变量、双变量、多变量分析

一个给 AI 工作台用的技能（skill）。只要说清数据文件、因变量（0/1）、哪些是连续自变量、哪些是分类自变量，Agent 就按固定规则写 do 文件、调用 Stata 执行，再从日志读回结果，写成 Markdown 表格。适用于 WorkBuddy、Claude Code、Codex 等支持 `SKILL.md` 的工作台。

## 它做哪三步

| 步骤 | 做法 |
| --- | --- |
| 单变量分析 | 连续变量报告均值、标准差；分类变量（含因变量）报告频数、百分比 |
| 双变量分析 | 各自变量分别与因变量比较：连续自变量按因变量分组做 t 检验；分类自变量做卡方检验，有单元格期望频数小于 5 时补报 Fisher 精确检验 |
| 多变量分析 | 全部自变量放入同一个二分类 logistic 回归，报告 OR、95% 置信区间与 p 值；连续变量直接进入，分类变量以 `i.` 进入 |

几条固定的规则：

- **不删观测**：先生成分析样本标记 `analysis`（因变量与全部自变量均非缺失记为 1），此后每条分析命令都带 `if analysis == 1`。
- **方法事先定好**：检验方法只看变量类型，不看结果；do 文件由模板生成，Agent 只改参数区。
- **数字有据可查**：do 文件末尾输出一段固定格式的“结果汇总”，写进 Markdown 的每个数字都取自这里。
- **只做这三步**：边际效应、稳健性检验、导出 Word、作图等，只有用户明确要求时才做（见 `references/optional-modules.md`）。

## 开始之前

- 本机装有 Stata。模板在 macOS 的 Stata 16 SE 上实测通过，其他版本与系统尚未测试。
- 让 Agent 能运行 Stata，以下两种方式任选其一：
  - Stata 连接器 [stata-mcp](https://github.com/SepineTam/mcp-for-stata)。日志由连接器自动保存，do 文件里不写 `log using`。项目路径须为全英文，否则回传结果会报编码错误。
  - 命令行批处理，例如 `stata-se -b do do/analysis.do`。日志生成在当前目录。
- 核心三步只用 Stata 自带命令，不需要安装外部命令包。

## 安装

**WorkBuddy**：在本仓库的 [Releases](../../releases) 页下载 `stata-uni-bi-multi-v1.0.0.zip`，然后在 WorkBuddy 的技能市场中选“添加技能 → 上传技能”，选中这个 zip。技能包按 WorkBuddy 官方说明的格式准备（`SKILL.md` 加 `manifest.yaml`），尚未在 WorkBuddy 中实测导入。

**Claude Code、Codex 等**：

```bash
npx skills add richardu8/stata-uni-bi-multi
```

也可以手动安装：把 `skills/stata-uni-bi-multi/` 整个文件夹复制到 `~/.claude/skills/`。

## 怎么用

对 Agent 说清数据、变量和产出位置即可，例如：

```text
用 stata-uni-bi-multi 技能分析 inputs/clhls2021_analysis.dta：
因变量 disabled；连续自变量 age edu；分类自变量 female urban a51。
可以修改数据库。分析命令存于 do/analysis.do；
结果写入“CLHLS2021-ADL失能影响因素分析.md”文末，标题为“五、数据分析结果”。
```

没有说明的项按缺省处理：
- 标记变量名为 `analysis`。
- 不修改数据文件。
- do 文件为 `do/analysis.do`。
- 结果写入 `results/analysis-results.md`。

分类变量默认以取值最小的类别为参照组。要换参照组，写成 `ib2.a51` 这样即可。

## 会得到什么

- **do 文件**：由模板生成，分为读入与检查、单变量、双变量、多变量、结果汇总五段。
- **运行日志**：含各命令的完整输出，以及末尾的结果汇总。
- **Markdown 结果**：样本说明与五张表，即连续变量描述统计、分类变量频数、t 检验、卡方检验、logistic 回归 OR。

## 示例

`examples/nlsw88/` 用 Stata 自带的 nlsw88 数据，以是否参加工会（union）为因变量，存有生成的 do 文件和写出的结果。复现步骤：

```stata
cd examples/nlsw88
mkdir inputs
sysuse nlsw88, clear
save "inputs/nlsw88.dta", replace
do do/analysis.do
```

## 文件结构

```text
skills/stata-uni-bi-multi/
├── SKILL.md                        # 技能说明：参数、步骤、排错、自检
├── manifest.yaml                   # WorkBuddy 技能包元数据
├── assets/analysis-template.do     # do 文件模板，只改参数区
└── references/
    ├── report-template.md          # 结果文件的写法与表格样式
    └── optional-modules.md         # 可选：OR 表导出、OR 图、稳健性检验
examples/nlsw88/                    # 公开数据示例
```

## 已知限制

- 只适用于二分类因变量；不处理抽样权数（svy）、面板与多层数据。
- t 检验为两组方差相等的 Student t 检验。
- 命令行批处理出错时，退出码可能仍为 0。是否出错要看日志中是否出现 `r(数字);`。
- 命令行（控制台）版 Stata 不能导出 PNG。可选模块的作图会同时导出 PDF。

## 借鉴

写作时读过以下 Stata 相关技能，借鉴了其中的做法。本项目与它们没有从属关系，也没有复制其原文。

| 来源 | 借鉴之处 |
| --- | --- |
| [nealcaren/social-data-analysis](https://github.com/nealcaren/social-data-analysis) 的 stata-analyst（MIT） | 用样本标记变量而不删观测；不悄悄剔除观测，交代样本量；找不到 Stata 时只交 do 文件，请用户运行 |
| stata-basic | 批处理执行、读日志；只在已知可能失败处用 `capture`；路径不写死；交付前的质量清单 |
| [dylantmoore/stata-skill](https://github.com/dylantmoore/stata-skill) | 缺失值视为无穷大、分类变量须加 `i.`、`capture` 会吞掉错误等常见陷阱；在 macOS 上定位 Stata 可执行文件 |
| [brycewang-stanford/auto-empirical-research-skills](https://github.com/brycewang-stanford/auto-empirical-research-skills) 的 Full-empirical-analysis-skill-Stata | do 文件分段骨架；所需外部命令包集中列出 |
| [aperivue/medsci-skills](https://github.com/aperivue/medsci-skills) 的 analyze-stats | 报告的每个数字都须来自已执行代码的输出；完全分离须查出并说明 |
| [alterlab-ieu/alterlab-academic-skills](https://github.com/alterlab-ieu/alterlab-academic-skills) 的 alterlab-test-selection-guard | 检验方法在看到 p 值之前按变量类型定好 |
| [zihaovistonwang/stata-ai-skill](https://github.com/zihaovistonwang/stata-ai-skill) | 命令用法不确定时先查帮助；安装外部命令包须经用户同意 |
| stata-did、stata-iv、stata-rd、stata-matching | 报告因估计而损失的样本量；交付前清单 |

与其中几个技能不同，本技能的 logistic 回归默认报告 OR，不报告平均边际效应。

## 许可证

MIT
