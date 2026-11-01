# stata-uni-bi-multi：用 Stata 做单变量、双变量、多变量分析

一个给 AI 工作台用的技能（skill）。只要说清数据文件、因变量及其类型、哪些是连续自变量、哪些是分类自变量，Agent 就按固定规则写 do 文件、调用 Stata 执行，再从日志读回结果，写成 Markdown 表格。适用于 WorkBuddy、Claude Code、Codex 等支持 `SKILL.md` 的工作台。

## 它做哪三步

| 步骤 | 做法 |
| --- | --- |
| 单变量分析 | 连续变量（含连续或计数因变量、生存时间）报告均值、标准差；分类变量（含二分类、有序、无序多分类因变量与失效指示变量）报告频数、百分比 |
| 双变量分析 | 各自变量分别与因变量比较，检验方法由因变量类型与自变量类型决定，见下表 |
| 多变量分析 | 全部自变量放入同一个回归模型，模型由因变量类型决定，同类模型中可另选，见下表 |

双变量检验：

| 因变量类型 | 连续自变量 | 分类自变量 |
| --- | --- | --- |
| 二分类 | 按因变量分两组的 t 检验 | 卡方检验；有单元格期望频数小于 5 时补报 Fisher 精确检验 |
| 连续 | Pearson 相关 | 两组用 t 检验，三组及以上用单因素方差分析 |
| 有序 | Spearman 等级相关 | 两组用 Wilcoxon 秩和检验，三组及以上用 Kruskal–Wallis 检验 |
| 无序多分类 | 自变量按因变量各类别分组的单因素方差分析 | 卡方检验；有单元格期望频数小于 5 时补报 Fisher 精确检验 |
| 计数（无暴露量） | Spearman 等级相关 | 两组用 Wilcoxon 秩和检验，三组及以上用 Kruskal–Wallis 检验 |
| 生存 | 单变量 Cox 回归，报告粗 HR | log-rank 检验 |

有暴露量（如人年）的计数因变量比较的是发生率：每个自变量单独进入同一计数模型，报告粗 IRR。

多变量模型（每种类型的第一个为缺省）：

| 因变量类型 | `model` | 报告的效应 |
| --- | --- | --- |
| 二分类 | `logit` | OR |
| 二分类 | `probit` | 系数 |
| 二分类 | `lpm`（线性概率模型，稳健标准误） | 系数（概率差） |
| 二分类 | `mpoisson`（修正泊松，稳健标准误） | RR |
| 连续 | `ols` | 系数 |
| 有序 | `ologit` | OR |
| 有序 | `oprobit` | 系数 |
| 无序多分类 | `mlogit` | RRR |
| 计数 | `nbreg` | IRR |
| 计数 | `poisson` | IRR |
| 生存 | `cox` | HR |

几条固定的规则：

- **不删观测**：先生成分析样本标记 `analysis`（所列变量均非缺失记为 1），此后每条分析命令都带 `if analysis == 1`。
- **方法事先定好**：检验与模型只看变量类型，不看结果；do 文件由模板生成，Agent 只改参数区。
- **数字有据可查**：do 文件末尾输出一段固定格式的“结果汇总”，写进 Markdown 的每个数字都取自这里。
- **只做这三步**：模型诊断、平均边际效应、导出 Word、作图、稳健性检验等，只有用户明确要求时才做（见 `references/optional-modules.md`）。

各模型的假定、标准误、诊断与解释要点及文献，见 `references/method-notes.md`。

## 开始之前

- 本机装有 Stata。模板在 macOS 的 Stata 16 SE 上实测通过，其他版本与系统尚未测试。
- 让 Agent 能运行 Stata，以下两种方式任选其一：
  - Stata 连接器 [stata-mcp](https://github.com/SepineTam/mcp-for-stata)。日志由连接器自动保存，do 文件里不写 `log using`。项目路径须为全英文，否则回传结果会报编码错误。
  - 命令行批处理，例如 `stata-se -b do do/analysis.do`。日志生成在当前目录。
- 三步分析只用 Stata 自带命令，不需要安装外部命令包；可选模块中的导出、作图与部分诊断要用 SSC 上的命令包。

## 安装

**WorkBuddy**：在本仓库的 [Releases](../../releases) 页下载最新版本的 `stata-uni-bi-multi-v….zip`，然后在 WorkBuddy 的技能市场中选“添加技能 → 上传技能”，选中这个 zip。技能包按 WorkBuddy 官方说明的格式准备（`SKILL.md` 加 `manifest.yaml`），尚未在 WorkBuddy 中实测导入。

**Claude Code、Codex 等**：

```bash
npx skills add richardu8/stata-uni-bi-multi
```

也可以手动安装：把 `skills/stata-uni-bi-multi/` 整个文件夹复制到 `~/.claude/skills/`。

## 怎么用

对 Agent 说清数据、因变量类型、变量和产出位置即可。二分类因变量的例子：

```text
用 stata-uni-bi-multi 技能分析 inputs/clhls2021_analysis.dta：
因变量 disabled（二分类）；连续自变量 age edu；分类自变量 female urban a51。
可以修改数据库。分析命令存于 do/analysis.do；
结果写入“CLHLS2021-ADL失能影响因素分析.md”文末，标题为“五、数据分析结果”。
```

其他类型只需说明类型和专用信息，例如：

- 计数因变量：“因变量 visits（计数），模型用负二项回归”。
- 有暴露量：“因变量 deaths（计数），暴露量 pyears”。
- 生存因变量：“失效变量 died，生存时间 studytime（生存分析）”。
- 需要聚类标准误：“按 prov 聚类”。

没有说明的项按缺省处理：
- 因变量类型为二分类，模型为该类型的第一个。
- 标准误为模型的常规标准误。
- 标记变量名为 `analysis`，不修改数据文件。
- do 文件为 `do/analysis.do`，结果写入 `results/analysis-results.md`。

分类变量默认以取值最小的类别为参照组。要换参照组，写成 `ib2.a51` 这样即可。

## 会得到什么

- **do 文件**：由模板生成，分为读入与检查、单变量、双变量、多变量、结果汇总五段。
- **运行日志**：含各命令的完整输出，以及末尾的结果汇总。
- **Markdown 结果**：样本说明、单变量表、双变量表、多变量表与表注；表的样式随因变量类型而定，见 `references/report-template.md`。

## 示例与测试

`examples/nlsw88/` 用 Stata 自带的 nlsw88 数据，以是否参加工会（union）为因变量，存有生成的 do 文件和写出的结果。复现步骤：

```stata
cd examples/nlsw88
mkdir inputs
sysuse nlsw88, clear
save "inputs/nlsw88.dta", replace
do do/analysis.do
```

11 种模型都用 Stata 自带数据实跑过：nlsw88 用于二分类、连续、有序、无序多分类、无暴露量的计数，census 用于有暴露量的计数，cancer 用于生存，auto 用于完全预测的情形。每种模型的关键数字都与直接执行的 Stata 命令核对一致。出错路径与可选模块也逐项测试过。

## 文件结构

```text
skills/stata-uni-bi-multi/
├── SKILL.md                        # 技能说明：参数、方法对照、步骤、排错、自检
├── manifest.yaml                   # WorkBuddy 技能包元数据
├── assets/analysis-template.do     # do 文件模板，只改参数区
└── references/
    ├── report-template.md          # 结果文件的写法与各类型的表格样式
    ├── method-notes.md             # 方法依据：假定、标准误、诊断、解释与文献
    └── optional-modules.md         # 可选：诊断、边际效应、导出、作图、稳健性检验
examples/nlsw88/                    # 公开数据示例
```

## 已知限制

- 只处理横截面数据；不处理抽样权数（svy）、面板与多层数据，也不做因果识别设计。
- t 检验为两组方差相等的 Student t 检验；方差分析附 Bartlett 检验，但不据此改换方法。
- 有序模型默认不检验平行线假定，Cox 模型默认不检验比例风险假定，都在可选模块中。
- 命令行批处理出错时，退出码可能仍为 0。是否出错要看日志中是否出现 `r(数字);`。
- 命令行（控制台）版 Stata 不能导出 PNG。可选模块的作图会同时导出 PDF。

## 借鉴

写作时读过以下 Stata 相关技能，借鉴了其中的做法。本项目与它们没有从属关系，也没有复制其原文。

| 来源 | 借鉴之处 |
| --- | --- |
| [nealcaren/social-data-analysis](https://github.com/nealcaren/social-data-analysis) 的 stata-analyst（MIT） | 用样本标记变量而不删观测；不悄悄剔除观测，交代样本量；计数模型按离散程度选 poisson 或负二项；伪 R² 不是 R²；聚类数少时的提醒 |
| stata-basic | 批处理执行、读日志；只在已知可能失败处用 `capture`；路径不写死；交付前的质量清单 |
| [dylantmoore/stata-skill](https://github.com/dylantmoore/stata-skill) | 缺失值视为无穷大、分类变量须加 `i.`、`capture` 会吞掉错误等常见陷阱；在 macOS 上定位 Stata 可执行文件 |
| [brycewang-stanford/auto-empirical-research-skills](https://github.com/brycewang-stanford/auto-empirical-research-skills) 的 Full-empirical-analysis-skill-Stata | do 文件分段骨架；所需外部命令包集中列出 |
| [aperivue/medsci-skills](https://github.com/aperivue/medsci-skills) 的 analyze-stats | 报告的每个数字都须来自已执行代码的输出；完全分离须查出并说明 |
| [alterlab-ieu/alterlab-academic-skills](https://github.com/alterlab-ieu/alterlab-academic-skills) 的 alterlab-test-selection-guard | 检验方法在看到 p 值之前按变量类型定好；按结局类型、组数选检验的决策树 |
| [zihaovistonwang/stata-ai-skill](https://github.com/zihaovistonwang/stata-ai-skill) | 命令用法不确定时先查帮助；安装外部命令包须经用户同意 |
| stata-did、stata-iv、stata-rd、stata-matching | 报告因估计而损失的样本量；交付前清单 |

方法上的依据来自 Stata 16 官方手册与若干方法文献，逐条列在 `references/method-notes.md`。与其中几个技能不同，本技能的 logistic 回归默认报告 OR，不报告平均边际效应；需要时在可选模块中计算。

## 更新记录

- **1.1.0**（2026-11-01）：因变量类型作为参数，支持二分类、连续、有序、无序多分类、计数（可含暴露量）、生存六类共 11 种模型，可选稳健或聚类标准误；新增方法依据；可选模块按模型分支，增加模型诊断与平均边际效应。
- **1.0.0**（2026-11-01）：二分类因变量的描述统计、t 检验与卡方检验、logistic 回归（OR）。

## 许可证

MIT
