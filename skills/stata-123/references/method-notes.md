# 方法依据

本文件说明模板中各项方法取舍的依据，供 Agent 写表注、回答用户追问时参考。每条只写所列来源能够支持的内容：
- Stata 官方手册：据 Stata 16 版 PDF 的相应条目，以“[R] ttest”“[SVY] svy: tabulate twoway”的形式注明；
- 期刊文献：据其摘要，摘要不可得的只据题名与出处；
- SSC 命令包：据 `ssc describe` 的说明；
- 实测结果：在 Stata 16 SE（macOS）上实际运行所见，注明“实测”。

核对日期为 2026 年 11 月 2 日（北京时间），检索来源为 Stata 16 手册、Crossref、PubMed、OpenAlex 与 SSC。

## 一、方法事先定好

双变量检验与回归模型按因变量类型、自变量类型以及有无抽样设计选定，在看到任何 p 值之前就已确定；同一类型内换模型须由用户依研究问题提出。这一做法借自 alterlab-test-selection-guard 技能“不在看到 p 值之后选检验”的原则。

## 二、双变量检验

- **t 检验**：模板缺省用两组方差相等的 Student t 检验。参数 `unequal` 设为 1 时，改用 `ttest` 的 `unequal` 选项，不假定两组方差相等，自由度按 Satterthwaite（1946）的近似公式计算。`ttest` 另有 `welch` 选项，自由度改按 Welch（1947）的公式计算（[R] ttest）；模板不用该选项。
- **单因素方差分析**：`oneway` 的输出附 Bartlett 方差齐性检验（[R] oneway），写结果时不据此改换方法。
- **卡方与 Fisher 精确检验**：`tabulate` 可同时给出 Pearson χ² 与 Fisher 精确检验（[R] tabulate twoway）。有单元格期望频数小于 5 时卡方近似欠佳，按常用的经验规则改报 Fisher 精确检验的双侧 p 值；模板只在需要时才计算精确检验，以免大样本多分类表的精确检验耗时过长。
- **log-rank 检验**：`sts test` 缺省即为 log-rank 检验，另提供 Wilcoxon–Breslow–Gehan 等检验（[ST] sts test）。

## 三、抽样调查数据

- **声明抽样设计**：填了权数、初级抽样单元（PSU）或分层变量中的任一项，模板即用 `svyset` 声明抽样设计，此后的估计都加 `svy` 前缀，标准误按设计计算（线性化方法）。只给权数时，每个观测各自作为一个抽样单元（实测）。
- **用 subpop() 而不用 if**：[SVY] svy estimation 指出，对子总体做估计时，用 `if` 限定可能得到错误的标准误：它与 `subpop()` 的标准误常常相同，多数时候略有差别，样本稀疏的子总体则可能差别明显，因此应当使用 `subpop()` 选项。模板的分析样本因此用 `svy, subpop(analysis):` 限定，同样不删除观测。
- **分类变量的检验**：`svy: tabulate` 缺省报告 Pearson χ²，经 Rao 与 Scott（1984）的二阶校正后转换为 F 统计量，自由度一般不是整数；手册依据模拟结果，建议在各种情形下都使用这一统计量（[SVY] svy: tabulate twoway）。Rao 与 Scott（1984）的摘要说明，抽样设计下 Pearson χ² 的渐近分布是若干独立 χ²(1) 的加权和，权数与设计效应有关，并据此给出校正方法。
- **连续变量的检验**：模板把连续自变量对因变量各类别作 `svy: regress`，再用 `testparm` 做设计校正的 F 检验；连续因变量与连续自变量之间，报告单变量加权回归的系数及其检验。
- **调整的 Wald 检验**：`svy` 估计后，模型整体检验与 `test`、`testparm` 缺省都用调整的 Wald 检验，统计量服从 F(k, d − k + 1)，其中 k 为检验的约束个数，d 为设计自由度，即 PSU 总数减分层数（[SVY] svy，所引依据为 Korn & Graubard, 1990）。模板的结果汇总据此写出分母自由度。
- **加权的描述统计**：结果汇总中的加权百分比、加权均值与加权标准差，用权数作 aweight 计算，只是点估计。点估计与 `svy: proportion`、`svy: mean` 相同（实测）。加权标准差即各组内以权数加权的标准差。`estat sd` 缺省依据另一种方差估计计算，结果可能与之不同（实测）；`estat sd, srssubpop` 则按子总体内简单随机抽样的方差估计计算（[SVY] estat）。
- **限制**：
  - `qreg` 不支持 `svy` 前缀（实测，Stata 提示 qreg is not supported by svy）。
  - 按子总体估计后，`estat gof` 不能使用（实测）。
  - 本模板的生存分析不接受抽样设计。
  - `margins` 用于抽样调查数据时，模板的可选模块加 `subpop()` 选项，使平均边际效应只在分析样本上计算。

## 四、二分类因变量

- **OR 与 RR**：结局发生率较高（高于约 10%）时，logistic 回归得到的调整 OR 不再近似 RR；结局越常见，OR 大于 1 时越高估 RR，小于 1 时越低估 RR（Zhang & Yu, 1998）。
- **修正泊松**：即配稳健误差方差的 Poisson 回归，可直接估计 RR，作者的模拟显示总样本量小至 100 时仍可靠（Zou, 2004）。数据有聚类时，在聚类层面计算三明治方差的中间项；模拟显示聚类总数不少于 50 时可靠（Zou & Donner, 2013）。模板中的 `mpoisson` 因此强制使用稳健或聚类标准误。
- **OR 的比较**：logistic 回归的估计值受模型遗漏变量的影响，即使这些变量与自变量无关也是如此；因此 OR 同时反映未观测异质性，不能直接在不同组、不同样本、不同时点或自变量不同的模型之间比较（Mood, 2010）。也有研究认为，这类担心多数情况下并不成立：只有关心潜在连续变量本身时第一种担心才有关系，而组间差异本就存在，只要估计正确就可以比较（Kuha & Mills, 2020）。模板的结果说明不作跨模型、跨组的 OR 比较，以回避这一争议。
- **概率尺度**：需要用概率差解释时，可报告平均边际效应（可选模块 B），或改用线性概率模型 `lpm`。线性概率模型的误差方差随自变量变化，模板为它强制使用稳健标准误。

## 五、连续因变量

- **分位数回归**：`qreg` 估计条件分布的分位数（缺省为中位数）与自变量的线性关系（[R] qreg）。模板以参数 `quantile` 指定分位数。结果汇总中的伪 R² 为 1 减去 `qreg` 输出中最小离差之和（Min sum of deviations）与原始离差之和（Raw sum of deviations）之比，与输出中的 Pseudo R2 一致（实测）。`qreg` 的 `vce()` 只接受常规与稳健两种，不接受聚类标准误（实测）。
- **删失数据**：`tobit` 用于在某一取值处删失的连续因变量（[R] tobit）。手册说明，Tobin（1958）最初用它分析耐用消费品的购买，购买额在 0 处左删失；关心的量可以是潜在的未删失结果，也可以是观测到的删失结果。模板报告的系数是对潜在变量的效应，结果汇总中标为“系数（潜变量）”；要得到对观测值的平均边际效应，见可选模块 B。删失点由用户以 `ll`、`ul` 给出，模板先检查有无超出删失点的观测。

## 六、有序因变量

- `ologit` 只用到因变量取值的大小顺序，取值越大代表等级越高（[R] ologit）。用无序的多项模型分析有序因变量，会丢弃顺序信息（同一条目）。
- 平行线假定（比例优势假定）的检验可用 Brant（1990）提出的方法。SSC 命令包 `oparallel` 在 ologit 之后给出似然比、score、Wald、Wolfe–Gould 与 Brant 检验；假定不成立时，可考虑 SSC 命令包 `gologit2` 估计的广义有序 logit 模型。[R] ologit 所列参考文献中也有 Fu（1998）的广义有序 logit，以及 Fullerton 与 Xu（2016）关于平行、部分平行与非平行有序模型的著作。

## 七、无序多分类因变量

- `mlogit` 不指定 `baseoutcome()` 时，以频数最多的结局为基准类别（[R] mlogit）。模板显式指定基准类别（缺省为最小取值），使结果不随样本构成改变。
- 对 IIA 假定的三种常用检验的模拟显示，其检验水准依赖自变量的数据结构；在设定正确的模型中，这些检验常在备选项明显不同时拒绝 IIA，在备选项近似可替代时又不拒绝。作者的结论是，基于限制选择集的 IIA 检验不适合实际应用（Cheng & Long, 2007）。模板因此不做 IIA 检验，也不以其结果取舍模型。

## 八、计数因变量

- 负二项模型在 alpha 为 0 时即为 Poisson 模型；`nbreg` 估计 lnalpha，并给出 alpha=0 的似然比检验（[R] nbreg）。模板把 `nbreg` 设为缺省，结果汇总中列出 alpha 及该检验。使用稳健、聚类标准误或抽样设计时，Stata 不报告该似然比检验。alpha 的估计值接近 0、置信区间无法计算时，说明数据没有过度离散。
- 选用 `poisson` 时，`estat gof` 给出偏差与 Pearson 拟合优度检验，用于判断数据是否服从 Poisson 分布（[R] poisson postestimation），见可选模块 A。
- 有暴露量（如人年、人口数）时，用 `exposure()` 把暴露量的对数作为偏移项，比较的是发生率；模板的双变量步骤因此改用单变量计数回归报告粗 IRR，不再用秩和检验比较计数本身。
- **零膨胀模型**：用于 0 值多于计数模型所能解释的计数数据。`zip`、`zinb` 假定多出的 0 来自 logit 或 probit 模型，其余计数分别来自 Poisson 或负二项模型（[R] zip、[R] zinb；[R] zip 所依的模型形式为 Lambert, 1992）。模板报告计数方程的 IRR，零膨胀方程的系数另列，为 logit 系数。Stata 16 中，对 `zip`、`zinb` 指定 `vuong` 选项时，程序提示“Vuong 检验不适合用于检验零膨胀”，只有另加 `forcevuong` 才执行（实测）；Wilson（2015）的题名即为“为检验零膨胀而误用非嵌套模型的 Vuong 检验”。模板不做 Vuong 检验。

## 九、生存因变量

- `estat phtest` 检验缩放 Schoenfeld 残差对时间回归的斜率是否为零，等价于检验对数风险比是否随时间不变；拒绝零斜率即提示比例风险假定不成立（[ST] stcox PH-assumption tests，依据 Grambsch & Therneau, 1994），见可选模块 A。
- **Weibull 模型**：`streg, distribution(weibull)` 为参数生存模型，缺省报告 HR，形状参数 p 另列（[ST] streg）。
- **竞争风险**：`stcrreg` 按 Fine 与 Gray（1999）的方法，对关注的失效事件的子分布风险（subhazard）建模；发生竞争事件的对象仍留在风险集中，结果为子分布风险比（SHR），解释方式与 Cox 回归的 HR 相近（[ST] stcrreg）。模板要求因变量取 0（删失）、1（关注的失效事件）与 `compete` 指定的竞争事件取值。

## 十、逐步加入变量与联合检验

- **同一样本**：参数 `blocks` 把自变量分组，模型 1 只含第一组，此后逐组加入。各模型都在同一分析样本上估计，样本量相同，结果可以并列比较。
- **增量检验**：每加入一组，在新模型中用 `testparm` 对新加入的各项做联合 Wald 检验，不用似然比检验，因此在稳健标准误与抽样设计下同样适用。
- **系数变化的解读**：logit 系数在自变量不同的模型之间不能直接比较（见第四节 Mood, 2010），加入变量前后 OR 的变化不宜直接解读为中介或混杂的大小。
- **多分类变量的联合检验**：三类及以上的分类自变量，模板在全模型中用 `testparm i.变量` 检验其各水平的系数是否同时为 0，作为该变量整体的检验，写在表注中。

## 十一、标准误

- 缺省为各模型的常规标准误。样本有聚类结构时用 `vce(cluster 聚类变量)`；聚类稳健推断的实际做法，可参见 MacKinnon 等（2023）的实践指南。聚类数很少时，常规聚类标准误不可靠，这一点借自 stata-analyst 技能的提醒；以修正泊松为例，Zou 与 Donner（2013）的模拟以不少于 50 个聚类为可靠的条件。
- 抽样调查数据的标准误由抽样设计决定，聚类即 PSU，模板不再接受 `vce` 参数。

## 十二、诊断与拟合

- logit 之后，`estat gof` 给出 Pearson 或 Hosmer–Lemeshow 拟合优度检验（[R] logistic postestimation）；`lroc` 给出 ROC 曲线下面积（[R] lroc）。
- Cox 回归之后，`estat concordance` 给出 Harrell C 统计量（[ST] stcox postestimation）。
- 伪 R² 不是 OLS 意义上的 R²，不作“解释方差”解读，这一点借自 stata-analyst 技能。生存模型的结果汇总不列伪 R²。

## 十三、异质性分析

可选模块 G 用两种方式考察关键自变量的效应是否因分组而不同：一是分组回归；二是在全样本模型中加入交互项，并对交互项做联合检验。logit 等非线性模型中，交互项检验的是对数发生比尺度上的差异，跨组比较 OR 的争议见第四节。因此该模块另给 `margins` 计算的各组平均边际效应及其差异，作为概率尺度上的比较。

## 十四、缺失值与多重插补

- 主分析为完整个案分析：只用所列变量均无缺失的观测，结果汇总列出各变量的缺失数。
- 可选模块 H 用多重插补做敏感性分析。[MI] 手册指出：
  - 插补模型必须包含与缺失机制有关的预测变量，并保留分析阶段要考察的数据特征；分析模型中的变量应当进入插补模型，分析模型的因变量也应始终进入插补模型（[MI] intro substantive、[MI] mi impute）。
  - 因变量本身有缺失时是否插补，文献中没有定论（[MI] mi impute）。
  - 缺失比例较低时，5 至 20 次插补可能就够；缺失比例较高时可能需要 100 次甚至更多，并建议改变插补次数，看结果是否变化（[MI] intro substantive）。

  模块因此只插补自变量，把因变量作为插补模型的预测变量，插补 20 次，并固定随机数种子。更多实践指导见 White、Royston 与 Wood（2011）。

## 参考文献

Brant, R. (1990). Assessing proportionality in the proportional odds model for ordinal logistic regression. *Biometrics*, *46*(4), 1171–1178. https://doi.org/10.2307/2532457

Cheng, S., & Long, J. S. (2007). Testing for IIA in the multinomial logit model. *Sociological Methods & Research*, *35*(4), 583–600. https://doi.org/10.1177/0049124106292361

Fine, J. P., & Gray, R. J. (1999). A proportional hazards model for the subdistribution of a competing risk. *Journal of the American Statistical Association*, *94*(446), 496–509. https://doi.org/10.1080/01621459.1999.10474144

Grambsch, P. M., & Therneau, T. M. (1994). Proportional hazards tests and diagnostics based on weighted residuals. *Biometrika*, *81*(3), 515–526. https://doi.org/10.1093/biomet/81.3.515

Korn, E. L., & Graubard, B. I. (1990). Simultaneous testing of regression coefficients with complex survey data: Use of Bonferroni *t* statistics. *The American Statistician*, *44*(4), 270–276. https://doi.org/10.1080/00031305.1990.10475737

Kuha, J., & Mills, C. (2020). On group comparisons with logistic regression models. *Sociological Methods & Research*, *49*(2), 498–525. https://doi.org/10.1177/0049124117747306

Lambert, D. (1992). Zero-inflated Poisson regression, with an application to defects in manufacturing. *Technometrics*, *34*(1), 1–14. https://doi.org/10.2307/1269547

MacKinnon, J. G., Nielsen, M. Ø., & Webb, M. D. (2023). Cluster-robust inference: A guide to empirical practice. *Journal of Econometrics*, *232*(2), 272–299. https://doi.org/10.1016/j.jeconom.2022.04.001

Mood, C. (2010). Logistic regression: Why we cannot do what we think we can do, and what we can do about it. *European Sociological Review*, *26*(1), 67–82. https://doi.org/10.1093/esr/jcp006

Rao, J. N. K., & Scott, A. J. (1984). On chi-squared tests for multiway contingency tables with cell proportions estimated from survey data. *The Annals of Statistics*, *12*(1), 46–60. https://doi.org/10.1214/aos/1176346391

Satterthwaite, F. E. (1946). An approximate distribution of estimates of variance components. *Biometrics Bulletin*, *2*(6), 110–114. https://doi.org/10.2307/3002019

StataCorp. (2019). *Stata 16 base reference manual*. Stata Press.

StataCorp. (2019). *Stata 16 multiple-imputation reference manual*. Stata Press.

StataCorp. (2019). *Stata 16 survey data reference manual*. Stata Press.

StataCorp. (2019). *Stata 16 survival analysis reference manual*. Stata Press.

Tobin, J. (1958). Estimation of relationships for limited dependent variables. *Econometrica*, *26*(1), 24–36. https://doi.org/10.2307/1907382

Welch, B. L. (1947). The generalization of “Student's” problem when several different population variances are involved. *Biometrika*, *34*(1–2), 28–35. https://doi.org/10.1093/biomet/34.1-2.28

White, I. R., Royston, P., & Wood, A. M. (2011). Multiple imputation using chained equations: Issues and guidance for practice. *Statistics in Medicine*, *30*(4), 377–399. https://doi.org/10.1002/sim.4067

Wilson, P. (2015). The misuse of the Vuong test for non-nested models to test for zero-inflation. *Economics Letters*, *127*, 51–53. https://doi.org/10.1016/j.econlet.2014.12.029

Zhang, J., & Yu, K. F. (1998). What's the relative risk? A method of correcting the odds ratio in cohort studies of common outcomes. *JAMA*, *280*(19), 1690–1691. https://doi.org/10.1001/jama.280.19.1690

Zou, G. (2004). A modified Poisson regression approach to prospective studies with binary data. *American Journal of Epidemiology*, *159*(7), 702–706. https://doi.org/10.1093/aje/kwh090

Zou, G. Y., & Donner, A. (2013). Extension of the modified Poisson regression model to prospective studies with correlated binary data. *Statistical Methods in Medical Research*, *22*(6), 661–670. https://doi.org/10.1177/0962280211427759
