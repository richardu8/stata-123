# 方法依据

本文件说明模板中各项方法取舍的依据，供 Agent 写表注、回答用户追问时参考。每条只写所列来源能够支持的内容：Stata 官方手册据 Stata 16 版 PDF 的相应条目，期刊文献据其摘要或题名，SSC 命令包据 `ssc describe` 的说明。核对日期为 2026 年 11 月 1 日（北京时间），检索来源为 Stata 16 手册、Crossref、PubMed、OpenAlex 与 SSC。

## 一、方法事先定好

双变量检验与回归模型按因变量类型和自变量类型选定，在看到任何 p 值之前就已确定；同一类型内换模型须由用户依研究问题提出。这一做法借自 alterlab-test-selection-guard 技能“不在看到 p 值之后选检验”的原则。

## 二、双变量检验

- **t 检验**：模板用两组方差相等的 Student t 检验；`ttest` 另有 `unequal` 选项，可放宽方差相等的假定（Stata 手册 [R] ttest）。需要时由用户指定，模板不自动切换。
- **单因素方差分析**：`oneway` 的输出附 Bartlett 方差齐性检验（[R] oneway），写结果时不据此改换方法。
- **卡方与 Fisher 精确检验**：`tabulate` 可同时给出 Pearson χ² 与 Fisher 精确检验（[R] tabulate twoway）。有单元格期望频数小于 5 时卡方近似欠佳，按常用的经验规则改报 Fisher 精确检验的双侧 p 值；模板只在需要时才计算精确检验，以免大样本多分类表的精确检验耗时过长。
- **log-rank 检验**：`sts test` 缺省即为 log-rank 检验，另提供 Wilcoxon–Breslow–Gehan 等检验（[ST] sts test）。

## 三、二分类因变量

- **OR 与 RR**：结局发生率较高（高于约 10%）时，logistic 回归得到的调整 OR 不再近似 RR；结局越常见，OR 大于 1 时越高估 RR，小于 1 时越低估 RR（Zhang & Yu, 1998）。
- **修正泊松**：即配稳健误差方差的 Poisson 回归，可直接估计 RR，作者的模拟显示总样本量小至 100 时仍可靠（Zou, 2004）。数据有聚类时，在聚类层面计算三明治方差的中间项；模拟显示聚类总数不少于 50 时可靠（Zou & Donner, 2013）。模板中的 `mpoisson` 因此强制使用稳健或聚类标准误。
- **OR 的比较**：logistic 回归的估计值受模型遗漏变量的影响，即使这些变量与自变量无关也是如此；因此 OR 同时反映未观测异质性，不能直接在不同组、不同样本、不同时点或自变量不同的模型之间比较（Mood, 2010）。也有研究认为，这类担心多数情况下并不成立：只有关心潜在连续变量本身时第一种担心才有关系，而组间差异本就存在，只要估计正确就可以比较（Kuha & Mills, 2020）。模板的结果说明不作跨模型、跨组的 OR 比较，以回避这一争议。
- **概率尺度**：需要用概率差解释时，可报告平均边际效应（可选模块 B），或改用线性概率模型 `lpm`。线性概率模型的误差方差随自变量变化，模板为它强制使用稳健标准误。

## 四、有序因变量

- `ologit` 只用到因变量取值的大小顺序，取值越大代表等级越高（[R] ologit）。用无序的多项模型分析有序因变量，会丢弃顺序信息（同一条目）。
- 平行线假定（比例优势假定）的检验可用 Brant（1990）提出的方法。SSC 命令包 `oparallel` 在 ologit 之后给出似然比、score、Wald、Wolfe–Gould 与 Brant 检验；假定不成立时，可考虑 SSC 命令包 `gologit2` 估计的广义有序 logit 模型。[R] ologit 所列参考文献中也有 Fu（1998）的广义有序 logit，以及 Fullerton 与 Xu（2016）关于平行、部分平行与非平行有序模型的著作。

## 五、无序多分类因变量

- `mlogit` 不指定 `baseoutcome()` 时，以频数最多的结局为基准类别（[R] mlogit）。模板显式指定基准类别（缺省为最小取值），使结果不随样本构成改变。
- 对 IIA 假定的三种常用检验的模拟显示，其检验水准依赖自变量的数据结构；在设定正确的模型中，这些检验常在备选项明显不同时拒绝 IIA，在备选项近似可替代时又不拒绝。作者的结论是，基于限制选择集的 IIA 检验不适合实际应用（Cheng & Long, 2007）。模板因此不做 IIA 检验，也不以其结果取舍模型。

## 六、计数因变量

- 负二项模型在 alpha 为 0 时即为 Poisson 模型；`nbreg` 估计 lnalpha，并给出 alpha=0 的似然比检验（[R] nbreg）。模板把 `nbreg` 设为缺省，结果汇总中列出 alpha 及该检验。使用稳健或聚类标准误时，Stata 不报告该似然比检验。
- 选用 `poisson` 时，`estat gof` 给出偏差与 Pearson 拟合优度检验，用于判断数据是否服从 Poisson 分布（[R] poisson postestimation），见可选模块 A。
- 有暴露量（如人年、人口数）时，用 `exposure()` 把暴露量的对数作为偏移项，比较的是发生率；模板的双变量步骤因此改用单变量计数回归报告粗 IRR，不再用秩和检验比较计数本身。

## 七、生存因变量

- `estat phtest` 检验缩放 Schoenfeld 残差对时间回归的斜率是否为零，等价于检验对数风险比是否随时间不变；拒绝零斜率即提示比例风险假定不成立（[ST] stcox PH-assumption tests，依据 Grambsch & Therneau, 1994），见可选模块 A。

## 八、标准误

- 缺省为各模型的常规标准误。样本有聚类结构时用 `vce(cluster 聚类变量)`；聚类稳健推断的实际做法，可参见 MacKinnon 等（2023）的实践指南。聚类数很少时，常规聚类标准误不可靠，这一点借自 stata-analyst 技能的提醒；以修正泊松为例，Zou 与 Donner（2013）的模拟以不少于 50 个聚类为可靠的条件。

## 九、诊断与拟合

- logit 之后，`estat gof` 给出 Pearson 或 Hosmer–Lemeshow 拟合优度检验（[R] logistic postestimation）。
- 伪 R² 不是 OLS 意义上的 R²，不作“解释方差”解读，这一点借自 stata-analyst 技能。

## 参考文献

Brant, R. (1990). Assessing proportionality in the proportional odds model for ordinal logistic regression. *Biometrics*, *46*(4), 1171–1178. https://doi.org/10.2307/2532457

Cheng, S., & Long, J. S. (2007). Testing for IIA in the multinomial logit model. *Sociological Methods & Research*, *35*(4), 583–600. https://doi.org/10.1177/0049124106292361

Grambsch, P. M., & Therneau, T. M. (1994). Proportional hazards tests and diagnostics based on weighted residuals. *Biometrika*, *81*(3), 515–526. https://doi.org/10.1093/biomet/81.3.515

Kuha, J., & Mills, C. (2020). On group comparisons with logistic regression models. *Sociological Methods & Research*, *49*(2), 498–525. https://doi.org/10.1177/0049124117747306

MacKinnon, J. G., Nielsen, M. Ø., & Webb, M. D. (2023). Cluster-robust inference: A guide to empirical practice. *Journal of Econometrics*, *232*(2), 272–299. https://doi.org/10.1016/j.jeconom.2022.04.001

Mood, C. (2010). Logistic regression: Why we cannot do what we think we can do, and what we can do about it. *European Sociological Review*, *26*(1), 67–82. https://doi.org/10.1093/esr/jcp006

StataCorp. (2019). *Stata 16 base reference manual*. Stata Press.

StataCorp. (2019). *Stata 16 survival analysis reference manual*. Stata Press.

Zhang, J., & Yu, K. F. (1998). What's the relative risk? A method of correcting the odds ratio in cohort studies of common outcomes. *JAMA*, *280*(19), 1690–1691. https://doi.org/10.1001/jama.280.19.1690

Zou, G. (2004). A modified Poisson regression approach to prospective studies with binary data. *American Journal of Epidemiology*, *159*(7), 702–706. https://doi.org/10.1093/aje/kwh090

Zou, G. Y., & Donner, A. (2013). Extension of the modified Poisson regression model to prospective studies with correlated binary data. *Statistical Methods in Medical Research*, *22*(6), 661–670. https://doi.org/10.1177/0962280211427759
