# 可选模块

只在用户要求时使用。代码接在 do 文件第（五）段之后，作为“（六）可选模块”。各模块按 `model` 分支，用到哪个模型就执行哪一支。每个模块都能单独使用，可以只取需要的几个。

## 沿用模板生成的内容

- **参数与变量**：`y`、`xcont`、`xcatv`（分类自变量名）、`xcati`（分类自变量的回归写法）、`flag`、`model`、`ytype`、`ename`、`ylevs`（因变量的取值）、`inflate`、`ll`、`ul`、`wt`、`svy`（1 为抽样调查数据）、`eqopt`。
- **样本限定**：一般数据用 `` `ifs' ``，即 `if analysis == 1`；抽样调查数据用 `` `sp' ``，即 `svy, subpop(analysis):`，此时 `` `ifs' `` 为空。
- **估计结果**：`ubm_main` 为全模型；逐步加入变量时另有 `ubm_m1` 至 `ubm_m{K}`，`` `X`K'' `` 为全模型的自变量。
- **命令写法**：`pat_logit`、`pat_mpoisson` 等是各模型命令的写法。辅助程序 `_ubm_mk` 把写法中的占位符换成实际内容：

```stata
_ubm_mk 宏名 "`pat_模型'" "抽样设计前缀" "因变量" "自变量" "样本条件" "标准误选项" "零膨胀方程自变量"
```

稳健性检验、异质性分析与多重插补都用它组成命令，只改其中一处，其余与主模型相同。

## 外部命令包

用到的外部命令包均来自 SSC：outreg2、estout、coefplot、oparallel、gologit2。各段在使用前检查，没有时安装。

Stata 连接器在默认权限下，装包须由用户确认。装包被拦截或断网时，请用户在 Stata 命令窗口运行 `ssc install 包名`，不要绕过拦截。SSC 连不上时的处理见 `stata-pitfalls.md`。

```stata
* ====== （六）可选模块 ======
capture mkdir "outputs"                                  // 存放导出的表与图；已存在则跳过
local mopt = cond(`svy', "subpop(`flag')", "")          // 抽样调查数据的 margins 须限定子总体
local infl = cond("`inflate'" == "", "`X`K''", "`inflate'")
local eo = cond(strpos("`ename'", "系数") == 1, "", "eform")
* 回归表的导出命令：有切点、多个方程或辅助参数的模型与逐步加入变量的多个模型用 esttab，其余用 outreg2
local exporter "outreg2"
if `K' > 1 | inlist("`model'", "ologit", "oprobit", "mlogit", "tobit", "zip", "zinb", "weibull", "nbreg") {
    local exporter "esttab"
}
```

## A. 模型诊断

检验只作报告，是否换模型由用户决定。各检验的含义见 `method-notes.md`。抽样调查数据按子总体估计后，`estat gof`、`estat vif` 等常规诊断不可用，本模块不执行。

```stata
* 【6-1】模型诊断：按所用模型执行相应的检验（一般数据）
estimates restore ubm_main
if `svy' {
    display as text "抽样调查数据按子总体估计，常规诊断命令不可用，本模块不执行"
}
else {
    if "`model'" == "ols" {
        estat vif                       // 方差膨胀因子：自变量间的共线性
        estat hettest                   // Breusch–Pagan / Cook–Weisberg 异方差检验
        estat ovtest                    // Ramsey RESET 检验：函数形式与遗漏的高次项
    }
    if "`model'" == "lpm" {
        estat vif
    }
    if inlist("`model'", "logit", "probit") {
        estat gof, group(10)            // Hosmer–Lemeshow 拟合优度检验
        lroc, nograph                   // ROC 曲线下面积：模型区分两类结局的能力
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
        estat concordance               // Harrell C 统计量：模型对生存时间排序的区分能力
    }
}
```

nbreg 的离散检验已在结果汇总中。mlogit 不做 IIA 检验，理由见 `method-notes.md`。下列模型没有对应的常规检验：oprobit、mpoisson、qreg、tobit、zip、zinb、weibull、crreg。零膨胀模型的 Vuong 检验，Stata 16 已提示“不适合用于检验零膨胀”。

平行线假定不成立、且用户决定改用广义有序 logit 时：

```stata
* 【6-2】广义有序 logit：autofit 只对不满足平行线假定的变量放宽限制（一般数据）
capture which gologit2
if _rc ssc install gologit2
gologit2 `y' `X`K'' `ifs', autofit or
```

## B. 平均边际效应

把效应换算到概率、计数或观测值的尺度上：
- 二分类模型：概率差；
- 有序与多项模型：落入各类别的概率差；
- 计数模型：事件数的平均变化；
- tobit：删失后观测值的平均变化。

OLS、lpm 与 qreg 的系数本身就是边际效应，不必再算。生存模型不在本模块之列。

```stata
* 【6-3】平均边际效应
estimates restore ubm_main
if inlist("`model'", "logit", "probit", "mpoisson", "poisson", "nbreg", "zip", "zinb") {
    margins, dydx(*) `mopt'
}
if inlist("`model'", "ologit", "oprobit", "mlogit") {
    foreach c of local ylevs {
        margins, dydx(*) predict(outcome(`c')) `mopt'
    }
}
if "`model'" == "tobit" {
    local lo = cond("`ll'" == "", ".", "`ll'")
    local hi = cond("`ul'" == "", ".", "`ul'")
    margins, dydx(*) predict(ystar(`lo', `hi')) `mopt'
}
```

## C. 导出回归表（Word）

单方程模型用 outreg2，导出为 `outputs/regression.doc`。以下情况改用 estout 包的 esttab，导出为 `outputs/regression.rtf`，去掉切点、零膨胀方程与辅助参数，只留主方程：
- 有切点、多个方程或辅助参数的模型，即 ologit、oprobit、mlogit、tobit、nbreg、zip、zinb、weibull；
- 逐步加入变量的多个模型。

比值类效应加 `eform`，并去掉 `eform` 时多出的空行（因变量、Cox 与竞争风险模型的 `_t`）。nbreg 不用 outreg2，因为它会把 lnalpha 取指数后列在表中，名称仍写 lnalpha。抽样调查数据的 `e(N)` 是全部观测数，子总体的观测数另列为 `e(N_sub)`。

```stata
* 【6-4】导出回归表
estimates restore ubm_main
if "`exporter'" == "esttab" {
    capture which esttab
    if _rc ssc install estout
    local mods ""
    forvalues k = 1/`K' {
        local mods `mods' ubm_m`k'
    }
    local kp "eqlabels(none)"
    if inlist("`model'", "ologit", "oprobit", "tobit", "nbreg", "weibull") local kp "drop(/:) eqlabels(none)"
    if "`model'" == "zinb" local kp "drop(inflate: /:) eqlabels(none)"
    if "`model'" == "zip"  local kp "drop(inflate:) eqlabels(none)"
    if "`model'" == "mlogit" {
        local baseeq : word `e(ibaseout)' of `e(eqnames)'
        local kp "unstack drop(`baseeq':)"
    }
    local bf = cond("`eo'" == "", "b(3) ci(3)", "b(2) ci(2)")
    local st "N, fmt(0)"
    if `svy' local st `"N_sub, labels("Subpop. obs") fmt(0)"'
    esttab `mods' using "outputs/regression.rtf", replace `eo' `bf' label nobaselevels `kp' stats(`st')
}
else {
    capture which outreg2
    if _rc ssc install outreg2
    local an = cond(`svy', "addstat(Subpop. obs, e(N_sub))", "")
    if inlist("`model'", "probit", "lpm", "ols", "qreg") {
        outreg2 using "outputs/regression.doc", replace dec(3) label ctitle(`y') `an'
    }
    if inlist("`model'", "logit", "mpoisson", "poisson") {
        outreg2 using "outputs/regression.doc", replace eform dec(2) label drop(`y') ctitle(`y') `an'
    }
    if "`model'" == "cox" {
        outreg2 using "outputs/regression.doc", replace eform dec(2) label drop(_t) ctitle(HR)
    }
    if "`model'" == "crreg" {
        outreg2 using "outputs/regression.doc", replace eform dec(2) label drop(_t) ctitle(SHR)
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
if inlist("`model'", "logit", "mpoisson", "poisson", "crreg") {
    coefplot, drop(_cons) eform xline(1, lpattern(dash)) xtitle("`ename'及95%置信区间")
}
if inlist("`model'", "ologit", "nbreg", "zip", "zinb") {
    coefplot, keep(`y':) drop(_cons) eform xline(1, lpattern(dash)) xtitle("`ename'及95%置信区间")
}
if "`model'" == "weibull" {
    coefplot, keep(_t:) drop(_cons) eform xline(1, lpattern(dash)) xtitle("HR及95%置信区间")
}
if "`model'" == "mlogit" {
    local baseeq : word `e(ibaseout)' of `e(eqnames)'
    coefplot, drop(`baseeq': _cons) eform xline(1, lpattern(dash)) xtitle("RRR及95%置信区间")
}
if "`model'" == "cox" {
    coefplot, eform xline(1, lpattern(dash)) xtitle("HR及95%置信区间")
}
if inlist("`model'", "probit", "lpm", "ols", "qreg") {
    coefplot, drop(_cons) xline(0, lpattern(dash)) xtitle("系数及95%置信区间")
}
if inlist("`model'", "oprobit", "tobit") {
    coefplot, keep(`y':) drop(_cons) xline(0, lpattern(dash)) xtitle("系数及95%置信区间")
}
graph export "outputs/effects.pdf", replace
capture graph export "outputs/effects.png", replace width(2000)
if _rc display as text "本次运行的 Stata 不能导出 PNG，已导出 PDF：outputs/effects.pdf"
```

## E. 稳健性检验

每一项所需的信息都由用户给出，不自行设定。下面的例子来自 CLHLS 失能分析，变量都是示例：`e1`—`e6` 为六项日常活动，`prov` 为省份，`edu` 为受教育年限，切点也由用户给出，使用时按用户的变量和规则替换。

各项都用 `_ubm_mk` 按主模型的写法重估，只改动检验的那一处，估计结果存为 `rb_` 开头的名称。导出时分两种情况：
- 主模型用 outreg2 导出时：各项用 outreg2 的 `append` 并入 C 的同一张表；
- 主模型用 esttab 导出时：最后由【6-14】把主模型与各项并成一张表。

写结果时另列一表，逐项说明与主模型相比，各效应的方向与显著性是否改变。新变量在分析样本内有缺失时，写明实际样本量。

1. **换因变量口径**：用户给出新口径的构造规则，如“六项日常活动中至少两项需要帮助才算失能”。

```stata
* 【6-6】新口径的因变量：数出每人需要帮助的项数，至少两项记 1
generate byte adl_n = 0
foreach v of varlist e1 e2 e3 e4 e5 e6 {
    replace adl_n = adl_n + 1 if inlist(`v', 2, 3)
}
generate byte disabled2 = (adl_n >= 2)
_ubm_mk c "`pat_`model''" "`sp'" "disabled2" "`X`K''" "`ifs'" "`vceopt'" "`infl'"
`c'
estimates store rb_dv
if "`exporter'" == "outreg2" {
    outreg2 using "outputs/regression.doc", append `eo' dec(2) label drop(disabled2) ctitle(disabled2)
}
```

2. **换标准误**：稳健标准误用 `vce(robust)`；聚类标准误用 `vce(cluster 变量)`，聚类变量由用户给出，如省份。抽样调查数据的标准误由抽样设计决定，不做这一项。

```stata
* 【6-7】稳健标准误与按省份聚类的标准误（一般数据）
_ubm_mk c "`pat_`model''" "" "`y'" "`X`K''" "`ifs'" "vce(robust)" "`infl'"
`c'
estimates store rb_robust
if "`exporter'" == "outreg2" {
    outreg2 using "outputs/regression.doc", append `eo' dec(2) label drop(`y') ctitle(vce(robust))
}
_ubm_mk c "`pat_`model''" "" "`y'" "`X`K''" "`ifs'" "vce(cluster prov)" "`infl'"
`c'
estimates store rb_cluster
if "`exporter'" == "outreg2" {
    outreg2 using "outputs/regression.doc", append `eo' dec(2) label drop(`y') ctitle(vce(cluster prov))
}
```

3. **连续自变量改为分组**：用户给出切点与组名。改组后的变量以 `i.` 进入，原连续变量从模型中去掉。

```stata
* 【6-8】受教育年限分四组：0 未上过学；1–6 小学；7–9 初中；10 及以上 高中及以上
recode edu (0 = 1) (1/6 = 2) (7/9 = 3) (10/max = 4), generate(edu4)
label define edu4lb 1 "未上过学" 2 "小学" 3 "初中" 4 "高中及以上", replace
label values edu4 edu4lb
tabulate edu edu4 if `flag' == 1, missing
local Xn : subinstr local X`K' "edu" "i.edu4", word      // 把整词 edu 换成 i.edu4
_ubm_mk c "`pat_`model''" "`sp'" "`y'" "`Xn'" "`ifs'" "`vceopt'" "`infl'"
`c'
estimates store rb_edu4
if "`exporter'" == "outreg2" {
    outreg2 using "outputs/regression.doc", append `eo' dec(2) label drop(`y') ctitle(edu4)
}
```

4. **换同类模型**：如 logit 换成修正泊松或线性概率模型，nbreg 换成 poisson，ologit 换成 oprobit。比较的是效应方向与显著性；不同模型的效应名称不同，不直接比较数值大小。

```stata
* 【6-9】二分类因变量换成修正泊松（RR）与线性概率模型（概率差）；一般数据用稳健标准误
local rv = cond(`svy', "", "vce(robust)")
_ubm_mk c "`pat_mpoisson'" "`sp'" "`y'" "`X`K''" "`ifs'" "`rv'" ""
`c'
estimates store rb_mpoisson
outreg2 using "outputs/regression.doc", append eform dec(2) label drop(`y') ctitle(mpoisson)
_ubm_mk c "`pat_lpm'" "`sp'" "`y'" "`X`K''" "`ifs'" "`rv'" ""
`c'
estimates store rb_lpm
outreg2 using "outputs/regression.doc", append dec(3) label ctitle(lpm)
```

主模型用 esttab 导出时，把主模型与各项稳健性检验并成一张表。效应尺度不同的替代模型（如 ologit 换成 oprobit）另表导出，不与比值类效应混排：

```stata
* 【6-14】主模型与稳健性检验并表（主模型用 esttab 导出时）
local kp "eqlabels(none)"
if inlist("`model'", "ologit", "oprobit", "tobit", "nbreg", "weibull") local kp "drop(/:) eqlabels(none)"
if "`model'" == "zinb" local kp "drop(inflate: /:) eqlabels(none)"
if "`model'" == "zip"  local kp "drop(inflate:) eqlabels(none)"
local bf = cond("`eo'" == "", "b(3) ci(3)", "b(2) ci(2)")
esttab ubm_main rb_* using "outputs/robustness.rtf", replace `eo' `bf' label nobaselevels `kp' stats(N, fmt(0))
```

## F. 分组描述图

因变量在分组变量各组的比例或均值：二分类因变量画取 1 的比例（%），连续与计数因变量画均值。可再按第二个分组变量分开。连续变量（如年龄）先按用户给出的组距分组，横轴标注各组下限；横轴标题按分组变量改写。抽样调查数据按权数加权，图只作描述，不作检验。

```stata
* 【6-10】分组描述图：例为按 5 岁年龄组与城乡分开的失能比例
capture drop ubm_grp                                     // ubm_ 开头的变量为本技能所建，可以重建
egen ubm_grp = cut(age) if `flag' == 1, at(65(5)110)     // 组距与起止由用户给出（例）
local g1 ubm_grp                 // 横轴的分组变量
local g2 urban                   // 第二个分组变量，可留空
tempvar yp
if "`ytype'" == "binary" {
    quietly generate double `yp' = 100 * `y' if `flag' == 1
    local ytit "`y' = 1 的比例（%）"
}
else {
    quietly generate double `yp' = `y' if `flag' == 1
    local ytit "`y' 的均值"
}
local wx = cond("`wt'" == "", "", "[aw = `wt']")
local gopt `"ytitle("`ytit'") b1title("年龄组下限（岁）") blabel(bar, format(%4.1f) size(vsmall))"'
if "`g2'" == "" {
    graph bar (mean) `yp' `wx' if `flag' == 1, over(`g1') `gopt'
}
else {
    graph bar (mean) `yp' `wx' if `flag' == 1, over(`g2') over(`g1') asyvars `gopt'   // 横轴为 g1，颜色区分 g2
}
graph export "outputs/group_means.pdf", replace
capture graph export "outputs/group_means.png", replace width(2000)
```

## G. 异质性分析

检验关键自变量 `key` 的效应是否因分组变量 `by` 而不同，`key` 与 `by` 都由用户给出。做两件事：
1. 在 `by` 的每一组内重估全模型，即分组回归，分组变量本身从模型中去掉。
2. 在全样本模型中加入 `by` 与 `key` 的交互项，联合检验交互项是否同时为 0。

logit 等非线性模型的交互项，检验的是对数发生比尺度上的差异，含义见 `method-notes.md`。需要在概率尺度上比较时，用最后一段 `margins` 求各组的平均边际效应之差。

```stata
* 【6-11】异质性分析
local key age                    // 关键自变量（例），须是 xcont 或 xcat 中的变量
local by  urban                  // 分组变量（例），须为分类变量
local kc : list key in xcont
local kpos : list posof "`key'" in xcatv
local keyterm = cond(`kc', "c.`key'", "`: word `kpos' of `xcati''")
local Xo ""
foreach t of local X`K' {
    local tv = substr("`t'", strpos("`t'", ".") + 1, .)
    if "`tv'" != "`by'" local Xo `Xo' `t'
}
* （1）分组回归
quietly levelsof `by' if `flag' == 1, local(blevs)
foreach l of local blevs {
    local cnd "`flag' == 1 & `by' == `l'"
    local sp1 = cond(`svy', "svy, subpop(if `cnd'):", "")
    local if1 = cond(`svy', "", "if `cnd'")
    local inf1 = cond("`inflate'" == "", "`Xo'", "`inflate'")
    _ubm_mk c "`pat_`model''" "`sp1'" "`y'" "`Xo'" "`if1'" "`vceopt'" "`inf1'"
    display _n as text "【分组回归】`by' = `l'：`c'"
    capture noisily `c'
    if _rc {
        display as error "`by' = `l' 一组的模型无法估计或未收敛（r(`=_rc')），该组结果不可用，须在结果中写明"
    }
    else {
        estimates store ubm_g`l'
    }
}
* （2）交互项检验
local Xi ""
foreach t of local Xo {
    local tv = substr("`t'", strpos("`t'", ".") + 1, .)
    if "`tv'" != "`key'" local Xi `Xi' `t'
}
local Xi `Xi' i.`by'##`keyterm'
local inf2 = cond("`inflate'" == "", "`Xi'", "`inflate'")
_ubm_mk c "`pat_`model''" "`sp'" "`y'" "`Xi'" "`ifs'" "`vceopt'" "`inf2'"
display _n as text "【交互模型】`c'"
`c'
estimates store ubm_int
_ubm_test "异质性-交互检验" "`by' × `key'" "i.`by'#`keyterm'" "`eqopt'"
* （3）概率尺度：各组 key 的平均边际效应及其差（logit、probit 等非线性模型）
if inlist("`model'", "logit", "probit", "mpoisson", "poisson", "nbreg") {
    margins `by', dydx(`key') `mopt'
    margins r.`by', dydx(`key') `mopt'
}
```

## H. 多重插补（缺失值的敏感性分析）

主分析是完整个案分析，即所列变量均无缺失的观测。本模块对自变量的缺失值做多重插补，再用同一模型估计，比较结论是否改变。
- **插补对象**：插补样本为因变量非缺失的观测，因变量本身不插补。连续自变量用预测均值匹配（pmm），二分类自变量用 logit，三类及以上用 mlogit；因变量与其余无缺失的自变量作为插补模型的预测变量。
- **插补设置**：插补 20 次，固定随机数种子，结果按 Rubin 规则合并。
- **适用范围**：只用于一般数据的非生存模型。代码在 `preserve` 与 `restore` 之间运行，不改动内存中的原数据，也不保存数据文件。

```stata
* 【6-12】多重插补（一般数据、非生存模型）
if `svy' | "`ytype'" == "survival" {
    display as text "本模块只用于一般数据的非生存模型，未执行"
}
else {
    preserve
    generate byte _mi_s = 1
    markout _mi_s `y' `exposure' `inflv'
    local imp ""
    foreach v in `xcont' `xcatv' {
        quietly count if missing(`v') & _mi_s == 1
        if r(N) > 0 local imp `imp' `v'
    }
    if "`imp'" == "" {
        display as text "插补样本中自变量没有缺失值，不需要插补"
    }
    else {
        local spec ""
        foreach v of local imp {
            local isc : list v in xcont
            if `isc' {
                local spec `spec' (pmm, knn(5)) `v'
            }
            else {
                quietly levelsof `v' if _mi_s == 1, local(lv)
                local mm = cond(`: word count `lv'' == 2, "logit", "mlogit")
                local spec `spec' (`mm') `v'
            }
        }
        local rhs = cond(inlist("`ytype'", "ordinal", "nominal"), "i.`y'", "`y'")
        foreach t in `xcont' `xcati' {
            local tv = substr("`t'", strpos("`t'", ".") + 1, .)
            local isimp : list tv in imp
            if !`isimp' local rhs `rhs' `t'
        }
        mi set mlong
        mi register imputed `imp'
        mi impute chained `spec' = `rhs' if _mi_s == 1, add(20) rseed(20261102) augment
        local eo ""
        if inlist("`model'", "logit", "ologit") local eo "or"
        if "`model'" == "mlogit" local eo "rrr"
        if inlist("`model'", "mpoisson", "poisson", "nbreg", "zip", "zinb") local eo "irr"
        _ubm_mk c "`pat_`model''" "" "`y'" "`X`K''" "if _mi_s == 1" "`vceopt'" "`infl'"
        mi estimate, `eo': `c'
    }
    restore
}
```

## I. 生存曲线

按某个分类自变量分组，画 Kaplan–Meier 生存曲线，图下附各时点的风险人数。竞争风险模型（crreg）不画 Kaplan–Meier 曲线，改画累积发生函数。

```stata
* 【6-13】生存曲线（一般数据）
local g drug                     // 分组变量（例），须为分类自变量
if "`model'" == "crreg" {
    estimates restore ubm_main
    quietly levelsof `g' if `flag' == 1, local(gl)
    local ats ""
    local j = 0
    foreach l of local gl {
        local ++j
        local ats `ats' at`j'(`g' = `l')
    }
    stcurve, cif `ats'
}
else {
    sts graph if `flag' == 1, by(`g') risktable
}
graph export "outputs/survival.pdf", replace
capture graph export "outputs/survival.png", replace width(2000)
```
