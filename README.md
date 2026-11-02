# stata-123：指定变量，即可完成单变量、双变量、多变量分析

向 AI 说明数据文件、因变量与自变量，即可由 Stata 依次完成三步分析，结果写成论文可用的表格。名字中的 1、2、3 即单变量、双变量、多变量。

```text
用 stata-123 分析 inputs/clhls2021_analysis.dta：
因变量 disabled（二分类）；连续自变量 age edu；分类自变量 female urban a51。
结果写入“CLHLS2021-ADL失能影响因素分析.md”文末，标题为“五、数据分析结果”。
```

适用于 WorkBuddy、Claude Code、Codex 等支持技能（`SKILL.md`）的 AI 工作台。

## 它做哪三步

| 步骤 | 做法 | 写成的表 |
| --- | --- | --- |
| 1. 单变量 | 连续变量报告均值、标准差；分类变量报告频数、百分比 | 描述统计表 |
| 2. 双变量 | 每个自变量分别与因变量检验，检验方法按变量类型自动选定 | 组间比较表 |
| 3. 多变量 | 全部自变量进入同一回归模型，报告效应、95% 置信区间与 p 值 | 回归结果表 |

## 优势

- **一个参数换一类因变量**：二分类、连续、有序、无序多分类、计数、生存六类，共 17 种回归模型。检验与模型随类型自动切换，见下表。
- **方法事先定好**：用哪种检验、哪种模型只看变量类型，不看结果，避免依据显著性挑选方法。
- **数字有据可查**：全部命令保存在 do 文件中；写进表格的每个数字都取自日志末尾的结果汇总，可以逐一核对。
- **不删观测**：分析样本用标记变量限定。一般数据各命令带 `if analysis == 1`，抽样调查数据用 `subpop()`，原数据完整保留。
- **适用于调查数据**：
  - 填上权数、PSU、分层，检验与回归即按抽样设计计算；
  - 可以逐步加入变量，结果并成嵌套模型表；
  - 可选聚类、稳健标准误。
- **实测核对**：
  - 17 种模型都用公开数据实跑，关键数字与直接执行的 Stata 命令逐项一致；
  - 50 个测试案例随仓库提供，改版后一条命令即可回归测试；
  - 在 CLHLS 数据上，结果与手写的 do 文件逐项一致。

## 支持的模型

| 因变量 | 可选模型（第一个为缺省） | 报告 |
| --- | --- | --- |
| 二分类 | logit、probit、线性概率模型、修正泊松 | OR、系数、概率差、RR |
| 连续 | OLS、分位数回归、Tobit | 系数 |
| 有序 | ologit、oprobit | OR、系数 |
| 无序多分类 | mlogit | RRR |
| 计数 | 负二项、泊松、零膨胀负二项、零膨胀泊松（可含暴露量） | IRR |
| 生存 | Cox、Weibull、竞争风险（Fine–Gray） | HR、SHR |

用户提出时还可以做（可选模块）：
- 模型诊断、平均边际效应；
- 导出 Word 表、效应图；
- 稳健性检验，即换口径、换标准误、换分组、换模型；
- 分组描述图、异质性分析；
- 多重插补、生存曲线。

## 安装

- **WorkBuddy**：在 [Releases](../../releases) 下载最新的 `stata-123-v….zip`，在技能市场选“添加技能 → 上传技能”。
- **Claude Code、Codex 等**：运行下面的命令，或把 `skills/stata-123/` 文件夹复制到 `~/.claude/skills/`。

  ```bash
  npx skills add richardu8/stata-123
  ```

运行需要本机装有 Stata。让 AI 调用 Stata 有两种方式：
- 接入 Stata 连接器 [stata-mcp](https://github.com/SepineTam/mcp-for-stata)，项目路径须为全英文；
- 命令行批处理。

三步分析只用 Stata 自带命令，可选模块的导出与作图要用 SSC 命令包。

## 用法

开头的例子是最简单的用法。其他情况在提示词里加一句即可：

| 情况 | 提示词中加上 |
| --- | --- |
| 换模型 | “模型用修正泊松” |
| 调查数据 | “权数 finalwgt，PSU psuid，分层 stratid” |
| 逐步加入变量 | “模型 1 放 age female，模型 2 加 urban a51，模型 3 加 edu” |
| 聚类标准误 | “按 prov 聚类” |
| 计数数据有暴露量 | “暴露量 pyears” |
| 生存数据 | “失效变量 died，生存时间 studytime” |
| 竞争风险 | “生存时间 dftime，failtype 取 1 为关注事件、2 为竞争事件” |

没有说明的按缺省处理：
- 分类变量以取值最小的类别为参照组；
- 标准误为模型的常规标准误；
- 不修改数据文件；
- 命令存于 `do/analysis.do`，结果写入 `results/analysis-results.md`。

## 会得到什么

- `do/analysis.do`：可在 Stata 中直接重跑的完整命令。
- 运行日志：各命令的完整输出，末尾附结果汇总。
- Markdown 结果：样本说明、描述统计表、双变量表、回归表，表注写明检验方法、标准误与模型拟合。示例见 [`examples/nlsw88/results/analysis-results.md`](examples/nlsw88/results/analysis-results.md)。

## 不做什么

- 面板固定效应与随机效应、多层模型、结构方程；
- 工具变量、双重差分、断点回归、匹配等因果识别设计。

## 说明

- 在 macOS 的 Stata 16 SE 上实测，其他版本与系统尚未测试。
- WorkBuddy 的上传导入尚未实测。
- 回归结果表示条件关联，技能写结果时不作因果表述。

## 文件

```text
skills/stata-123/
├── SKILL.md                         # 技能说明：参数、方法对照、步骤、排错、自检
├── manifest.yaml                    # WorkBuddy 技能包元数据
├── assets/analysis-template.do      # do 文件模板，只改参数区
└── references/
    ├── report-template.md           # 结果表格的写法
    ├── method-notes.md              # 方法依据与文献
    ├── optional-modules.md          # 可选模块
    └── stata-pitfalls.md            # Stata 常见陷阱
examples/nlsw88/                     # 公开数据示例
tests/                               # 回归测试：50 个案例与基准结果
```

## 借鉴

写作时读过下列 Stata 相关技能，借鉴其做法，没有复制原文：
- [nealcaren/social-data-analysis](https://github.com/nealcaren/social-data-analysis) 的 stata-analyst；
- [dylantmoore/stata-skill](https://github.com/dylantmoore/stata-skill)；
- [brycewang-stanford/auto-empirical-research-skills](https://github.com/brycewang-stanford/auto-empirical-research-skills)；
- [aperivue/medsci-skills](https://github.com/aperivue/medsci-skills)；
- [alterlab-ieu/alterlab-academic-skills](https://github.com/alterlab-ieu/alterlab-academic-skills)；
- [zihaovistonwang/stata-ai-skill](https://github.com/zihaovistonwang/stata-ai-skill)；
- stata-basic、stata-did、stata-iv、stata-rd、stata-matching。

方法依据来自 Stata 16 官方手册与方法文献，逐条列在 `references/method-notes.md`。

## 更新记录

- **2.0.0**（2026-11-02）：
  - 更名为 stata-123；
  - 新增复杂抽样设计、逐步加入变量、联合检验、缺失情况报告、不假定方差相等的 t 检验；
  - 新增分位数回归、Tobit、零膨胀负二项与泊松、Weibull、竞争风险 6 种模型；
  - 新增分组描述图、异质性分析、多重插补、生存曲线 4 个可选模块；
  - 新增常见陷阱清单与回归测试。
- **1.1.0**（2026-11-01）：因变量类型作为参数，支持 11 种模型。
- **1.0.0**（2026-11-01）：二分类因变量的三步分析。

## 许可证

MIT
