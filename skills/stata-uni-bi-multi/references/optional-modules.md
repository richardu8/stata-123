# 可选模块

只在用户明确要求时使用。代码接在 do 文件第（五）段之后，作为“（六）可选模块”，沿用参数区与第（一）至（四）段生成的 `y`、`xcont`、`xcati`、`flag`、`vceopt`、`model`、`ename`、`ylevs` 与已存的估计结果 `ubm_main`；每条分析命令同样带 `if analysis == 1`（或所设的标记名）。各模块按 `model` 分支，用到哪个模型就执行哪一支。

部分模块要用外部命令包：outreg2、estout、coefplot、oparallel、gologit2，都来自 SSC。Stata 连接器在默认权限下装包须由用户确认；装包被拦截或断网时，请用户在 Stata 命令窗口自行运行 `ssc install 包名`，不要绕过拦截。

```stata
* ====== （六）可选模块 ======
capture mkdir "outputs"      // 存放导出的表与图；已存在则跳过
```

## A. 模型诊断

各检验的含义见 `method-notes.md`。检验只作报告，是否换模型由用户决定。

```stata
* 【6-1】模型诊断：按所用模型执行相应的检验
estimates restore ubm_main
if "`model'" == "ols" {
    estat vif                       // 方差膨胀因子：自变量间的共线性
    estat hettest                   // Breusch–Pagan / Cook–Weisberg 异方差检验
}
if "`model'" == "lpm" {
    estat vif
}
if inlist("`model'", "logit", "probit") {
    estat gof, group(10)            // Hosmer–Lemeshow 拟合优度检验
}
if "`model'" == "ologit" {
    capture which oparallel
    if _rc ssc install oparallel
    oparallel                       // 平行线假定：似然比、score、Wald、Wolfe–Gould、Brant 检验
}
if "`model'" == "poisson" {
    estat gof                       // 偏差与 Pearson 拟合优度：是否服从泊松分布
}
if "`model'" == "cox" {
    estat phtest, detail            // 比例风险假定：各变量与整体检验
}
```

nbreg 的离散检验已在结果汇总中；mlogit 不做 IIA 检验，理由见 `method-notes.md`；oprobit 与 mpoisson 没有对应的常规检验。

平行线假定不成立、且用户决定改用广义有序 logit 时：

```stata
* 【6-2】广义有序 logit：autofit 只对不满足平行线假定的变量放宽限制
capture which gologit2
if _rc ssc install gologit2
gologit2 `y' `xcont' `xcati' if `flag' == 1, autofit or
```

## B. 平均边际效应

把效应换算到概率或计数的尺度上：二分类模型为概率差，有序与多项模型为落入各类别的概率差，计数模型为事件数的平均变化。OLS 与 lpm 的系数本身就是边际效应，不必再算。

```stata
* 【6-3】平均边际效应
estimates restore ubm_main
if inlist("`model'", "logit", "probit", "poisson", "nbreg") {
    margins, dydx(*)
}
if inlist("`model'", "ologit", "oprobit", "mlogit") {
    foreach c of local ylevs {
        margins, dydx(*) predict(outcome(`c'))
    }
}
```

## C. 导出回归表（Word）

单方程模型用 outreg2；有序与多项模型含切点或多个方程，用 estout 包的 esttab。比值类效应加 `eform`，并去掉 `eform` 时多出的空行（因变量、nbreg 的 lnalpha、Cox 的 `_t`）。

```stata
* 【6-4】导出回归表
estimates restore ubm_main
if inlist("`model'", "ologit", "oprobit", "mlogit") {
    capture which esttab
    if _rc ssc install estout
    if "`model'" == "ologit" {
        esttab using "outputs/regression.rtf", replace eform b(2) ci(2) label nobaselevels keep(`y':)
    }
    if "`model'" == "oprobit" {
        esttab using "outputs/regression.rtf", replace b(3) ci(3) label nobaselevels keep(`y':)
    }
    if "`model'" == "mlogit" {
        local baseeq : word `e(ibaseout)' of `e(eqnames)'
        esttab using "outputs/regression.rtf", replace eform unstack b(2) ci(2) label nobaselevels drop(`baseeq':)
    }
}
else {
    capture which outreg2
    if _rc ssc install outreg2
    if inlist("`model'", "probit", "lpm", "ols") {
        outreg2 using "outputs/regression.doc", replace dec(3) label ctitle(`y')
    }
    if inlist("`model'", "logit", "mpoisson", "poisson") {
        outreg2 using "outputs/regression.doc", replace eform dec(2) label drop(`y') ctitle(`y')
    }
    if "`model'" == "nbreg" {
        outreg2 using "outputs/regression.doc", replace eform dec(2) label eqkeep(`y') drop(`y') ctitle(`y')
    }
    if "`model'" == "cox" {
        outreg2 using "outputs/regression.doc", replace eform dec(2) label drop(_t) ctitle(HR)
    }
}
```

## D. 效应图

比值类效应以 1 为参照线，系数类效应以 0 为参照线。命令行（控制台）版 Stata 不能导出 PNG，因此先导出 PDF。

```stata
* 【6-5】效应图
capture which coefplot
if _rc ssc install coefplot
estimates restore ubm_main
if inlist("`model'", "logit", "mpoisson", "poisson") {
    coefplot, drop(_cons) eform xline(1, lpattern(dash)) xtitle("`ename'及95%置信区间")
}
if inlist("`model'", "ologit", "nbreg") {
    coefplot, keep(`y':) drop(_cons) eform xline(1, lpattern(dash)) xtitle("`ename'及95%置信区间")
}
if "`model'" == "mlogit" {
    local baseeq : word `e(ibaseout)' of `e(eqnames)'
    coefplot, drop(`baseeq': _cons) eform xline(1, lpattern(dash)) xtitle("RRR及95%置信区间")
}
if "`model'" == "cox" {
    coefplot, eform xline(1, lpattern(dash)) xtitle("HR及95%置信区间")
}
if inlist("`model'", "probit", "lpm", "ols") {
    coefplot, drop(_cons) xline(0, lpattern(dash)) xtitle("系数及95%置信区间")
}
if "`model'" == "oprobit" {
    coefplot, keep(`y':) xline(0, lpattern(dash)) xtitle("系数及95%置信区间")
}
graph export "outputs/effects.pdf", replace
capture graph export "outputs/effects.png", replace width(2000)
if _rc display as text "本次运行的 Stata 不能导出 PNG，已导出 PDF：outputs/effects.pdf"
```

## E. 稳健性检验

每一项所需的信息都由用户给出，不自行设定。用所用模型的命令重跑，只改动检验的那一处；单方程模型的结果可用 outreg2 的 `append` 并入 C 的同一张表。写结果时另列一表，逐项说明与主模型相比，各效应的方向与显著性是否改变。新变量在分析样本内有缺失时，写明实际样本量。下面的例子以二分类 logit 为例，`e1`—`e6`、`prov`、`edu` 与切点都是示例，按用户给出的变量和规则替换。

1. **换因变量口径**：用户给出新口径的构造规则，如“六项日常活动中至少两项需要帮助才算失能”。

```stata
* 【6-6】新口径的因变量：数出每人需要帮助的项数，至少两项记 1
generate byte adl_n = 0
foreach v of varlist e1 e2 e3 e4 e5 e6 {
    replace adl_n = adl_n + 1 if inlist(`v', 2, 3)
}
generate byte disabled2 = (adl_n >= 2)
logit disabled2 `xcont' `xcati' if `flag' == 1, or `vceopt'
outreg2 using "outputs/regression.doc", append eform dec(2) label drop(disabled2) ctitle(disabled2)
```

2. **换标准误**：稳健标准误用 `vce(robust)`；聚类标准误用 `vce(cluster 变量)`，聚类变量由用户给出，如省份。

```stata
* 【6-7】稳健标准误与按省份聚类的标准误
logit `y' `xcont' `xcati' if `flag' == 1, or vce(robust)
outreg2 using "outputs/regression.doc", append eform dec(2) label drop(`y') ctitle(vce(robust))
logit `y' `xcont' `xcati' if `flag' == 1, or vce(cluster prov)
outreg2 using "outputs/regression.doc", append eform dec(2) label drop(`y') ctitle(vce(cluster prov))
```

3. **连续自变量改为分组**：用户给出切点与组名。改组后的变量以 `i.` 进入，原连续变量从模型中去掉。

```stata
* 【6-8】受教育年限分四组：0 未上过学；1–6 小学；7–9 初中；10 及以上 高中及以上
recode edu (0 = 1) (1/6 = 2) (7/9 = 3) (10/max = 4), generate(edu4)
label define edu4lb 1 "未上过学" 2 "小学" 3 "初中" 4 "高中及以上", replace
label values edu4 edu4lb
tabulate edu edu4 if `flag' == 1, missing
local old edu                            // 被替换的连续变量
local xcont_noedu : list xcont - old     // list 运算的两边都须是宏名
logit `y' `xcont_noedu' i.edu4 `xcati' if `flag' == 1, or `vceopt'
outreg2 using "outputs/regression.doc", append eform dec(2) label drop(`y') ctitle(edu4)
```

4. **换同类模型**：如 logit 换成修正泊松或线性概率模型，nbreg 换成 poisson，ologit 换成 oprobit。比较的是效应方向与显著性，不同模型的效应名称不同，不直接比较数值大小。

```stata
* 【6-9】二分类因变量换成修正泊松（RR）与线性概率模型（概率差），均用稳健标准误
poisson `y' `xcont' `xcati' if `flag' == 1, irr vce(robust)
outreg2 using "outputs/regression.doc", append eform dec(2) label drop(`y') ctitle(mpoisson)
regress `y' `xcont' `xcati' if `flag' == 1, vce(robust)
outreg2 using "outputs/regression.doc", append dec(3) label ctitle(lpm)
```
