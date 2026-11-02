* =============================================================
* stata-123：单变量、双变量、多变量分析
* 日期：2026-11-02
* 用途：按因变量类型做描述统计、双变量检验与多变量回归
* 输入：参数区 data 指定的数据文件
* 输出：运行日志（Stata 连接器自动保存；命令行批处理在当前目录生成同名 .log）
* 来源：stata-123 技能 2.0.0 的模板，只改参数区，其余各段不改
* 说明：在项目根目录运行，路径相对于项目根目录；本文件不写 log using；
*       分析样本用标记变量限定：一般数据的各分析命令带 if 条件，抽样调查数据的
*       估计命令用 subpop()，都不删除任何观测
* =============================================================

clear all
set more off
set varabbrev off      // 变量名须写全，不按缩写匹配
set linesize 255       // 结果汇总每条占一行，不折行

* ======================= 参数区：只改这一段 =======================
* —— 基本参数
local data     "inputs/nlsw88.dta"      // 数据文件（例：inputs/clhls2021_analysis.dta）
local ytype    binary                   // 因变量类型：binary continuous ordinal nominal count survival
local model                             // 模型；留空用该类型的缺省模型（见下方对照）
local y        union                    // 因变量；survival 时为失效指示变量（例：disabled）
local xcont    age grade wage           // 连续自变量，可留空（例：age edu）
local xcat     race married collgrad south // 分类自变量，可留空；改参照组写 ib#.变量名（例：female urban a51）
* —— 可选：模型设定
local blocks                            // 逐步加入的变量组，组间用 | 分隔（例：age female | urban a51 | edu）；留空只估计全模型
local vce                               // 标准误：留空为模型缺省；robust；cluster 聚类变量名
local unequal  0                        // 1＝t 检验不假定两组方差相等（自由度用 Satterthwaite 近似）
* —— 可选：复杂抽样设计（填任一项即按抽样设计分析）
local wt                                // 抽样权数（pweight）
local psu                               // 初级抽样单元
local strata                            // 分层变量
* —— 只用于特定类型或模型
local time                              // survival：生存时间变量
local compete                           // survival 的 crreg：竞争事件在因变量中的取值（例：2）
local exposure                          // count：暴露量变量（如人年），可留空
local inflate                           // zip、zinb：零膨胀方程的自变量，留空用全部自变量
local base                              // nominal：基准类别的取值，留空用最小取值
local quantile                          // qreg：分位数，留空为 0.5（中位数）
local ll                                // tobit：左删失点（例：0）
local ul                                // tobit：右删失点
* —— 样本标记
local flag     analysis                 // 分析样本标记变量名
local savedata 0                        // 1＝把标记变量存回数据文件；0＝不改数据文件
* ----------------------------------------------------------------
* 因变量类型与可选模型（排在第一个的是缺省模型）：
*   binary      logit（OR）  probit  lpm（线性概率模型）  mpoisson（修正泊松，RR）
*   continuous  ols  qreg（分位数回归）  tobit（删失数据）
*   ordinal     ologit（OR）  oprobit
*   nominal     mlogit（RRR）
*   count       nbreg（IRR）  poisson（IRR）  zinb  zip（零膨胀，IRR）
*   survival    cox（HR）  weibull（HR）  crreg（竞争风险，SHR）
* ================================================================


* ====== 辅助程序：只用于结果汇总的数字格式与逐项列出，不做分析 ======

capture program drop _ubm_num
program define _ubm_num
    * 效应值格式：比值类保留两位小数、系数类保留三位（dec）；绝对值小于 0.01 时保留两位
    * 有效数字；小于 0.0001 或不小于 10000 时用科学计数
    args mac x dec
    if "`dec'" == "" local dec 2
    if missing(`x') {
        c_local `mac' "."
    }
    else if `x' != 0 & abs(`x') < 0.0001 {
        c_local `mac' = strtrim(string(`x', "%12.1e"))
    }
    else if `x' != 0 & abs(`x') < 0.01 {
        local d = ceil(-log10(abs(`x'))) + 1
        c_local `mac' = strtrim(string(`x', "%20.`d'f"))
    }
    else if abs(`x') >= 10000 {
        c_local `mac' = strtrim(string(`x', "%12.2e"))
    }
    else {
        c_local `mac' = strtrim(string(`x', "%12.`dec'f"))
    }
end

capture program drop _ubm_p
program define _ubm_p
    * p 值格式：三位小数；小于 0.001 写 <0.001
    args mac x
    if missing(`x') {
        c_local `mac' "."
    }
    else if `x' < 0.001 {
        c_local `mac' "<0.001"
    }
    else {
        c_local `mac' = strtrim(string(`x', "%12.3f"))
    }
end

capture program drop _ubm_df
program define _ubm_df
    * 自由度格式：整数原样写出；非整数（不假定方差相等的 t 检验、设计校正检验）保留两位小数
    args mac x
    if missing(`x') {
        c_local `mac' "."
    }
    else if `x' == int(`x') {
        c_local `mac' = strtrim(string(`x', "%12.0f"))
    }
    else {
        c_local `mac' = strtrim(string(`x', "%12.2f"))
    }
end

capture program drop _ubm_tsum
program define _ubm_tsum
    * t 检验的汇总行：outvar 按 grpvar 分两组；uneq 为 1 时不假定两组方差相等
    args outvar grpvar flag uneq
    local vtxt = cond("`uneq'" == "1", "不假定相等（Satterthwaite 自由度）", "相等")
    local uneq = cond("`uneq'" == "1", "unequal", "")
    quietly ttest `outvar' if `flag' == 1, by(`grpvar') `uneq'
    local n1 = r(N_1)
    local n2 = r(N_2)
    local m1 = strtrim(string(r(mu_1), "%12.2f"))
    local s1 = strtrim(string(r(sd_1), "%12.2f"))
    local m2 = strtrim(string(r(mu_2), "%12.2f"))
    local s2 = strtrim(string(r(sd_2), "%12.2f"))
    local t  = strtrim(string(r(t), "%12.2f"))
    local pv = r(p)
    _ubm_df df `r(df_t)'
    _ubm_p p `pv'
    quietly levelsof `grpvar' if `flag' == 1, local(g)
    local g1 : word 1 of `g'
    local g2 : word 2 of `g'
    display as text "【双变量-t检验】`outvar' 按 `grpvar' 分组 | `grpvar'=`g1'：N=`n1' 均值=`m1' 标准差=`s1' | `grpvar'=`g2'：N=`n2' 均值=`m2' 标准差=`s2' | t=`t' | df=`df' | p=`p' | 方差=`vtxt'"
end

capture program drop _ubm_groups
program define _ubm_groups
    * 分组描述的汇总行：outvar 在 grpvar 各组的观测数、均值、标准差、中位数；
    * wt 非空时另给加权均值与加权标准差（权数作 aweight，只用于点估计）
    args outvar grpvar flag wt
    quietly levelsof `grpvar' if `flag' == 1, local(levs)
    foreach l of local levs {
        quietly summarize `outvar' if `grpvar' == `l' & `flag' == 1, detail
        local n  = r(N)
        local m  = strtrim(string(r(mean), "%12.2f"))
        local sd = strtrim(string(r(sd), "%12.2f"))
        local md = strtrim(string(r(p50), "%12.2f"))
        local w ""
        if "`wt'" != "" {
            quietly summarize `outvar' [aw = `wt'] if `grpvar' == `l' & `flag' == 1
            local wm = strtrim(string(r(mean), "%12.2f"))
            local ws = strtrim(string(r(sd), "%12.2f"))
            local w " | 加权均值=`wm' | 加权标准差=`ws'"
        }
        local lab : label (`grpvar') `l'
        local lab = cond("`lab'" == "`l'", "", "（`lab'）")
        display as text "【双变量-分组】`outvar' | `grpvar'=`l'`lab' | N=`n' | 均值=`m' | 标准差=`sd' | 中位数=`md'`w'"
    }
end

capture program drop _ubm_xtab
program define _ubm_xtab
    * 交叉表的汇总行：各行合计与各格频数，“分组”行附行百分比，“列”行附列百分比；
    * wt 非空时百分比为加权百分比（权数作 aweight，只用于点估计），频数仍为观测数
    args v y flag wt
    local wexp = cond("`wt'" == "", "", "[aw = `wt']")
    quietly levelsof `y' if `flag' == 1, local(ylevs)
    quietly levelsof `v' if `flag' == 1, local(levs)
    foreach l of local levs {
        quietly count if `v' == `l' & `flag' == 1
        local nl = r(N)
        local lab : label (`v') `l'
        local lab = cond("`lab'" == "`l'", "", "（`lab'）")
        local rcells ""
        local ccells ""
        foreach c of local ylevs {
            quietly count if `v' == `l' & `y' == `c' & `flag' == 1
            local nlc = r(N)
            tempvar ind
            quietly generate byte `ind' = (`y' == `c') if `v' == `l' & `flag' == 1
            quietly summarize `ind' `wexp'
            local rp = strtrim(string(100 * r(mean), "%12.1f"))
            drop `ind'
            quietly generate byte `ind' = (`v' == `l') if `y' == `c' & `flag' == 1
            quietly summarize `ind' `wexp'
            local cp = strtrim(string(100 * r(mean), "%12.1f"))
            drop `ind'
            local rcells "`rcells' | `y'=`c'：`nlc'（`rp'）"
            local ccells "`ccells' | `y'=`c'：`nlc'（`cp'）"
        }
        display as text "【双变量-卡方-分组】`v'=`l'`lab' | 合计=`nl'`rcells'"
        display as text "【双变量-卡方-列】`v'=`l'`lab' | 合计=`nl'`ccells'"
    }
end

capture program drop _ubm_effects
program define _ubm_effects
    * 逐项列出估计结果：tag 为汇总行标签，ename 为效应名称，T 为 r(table) 的副本，
    * flag 为分析样本标记；brief 为 1 时只列自变量（单变量回归的粗效应用），不列常数项
    * 与辅助参数。比值类模型中未取指数的列（如零膨胀方程）按系数列出
    args tag ename T flag brief
    local isratio = (strpos("`ename'", "系数") != 1)
    local erow = rownumb(`T', "eform")
    local cn : colnames `T'
    local ce : coleq `T'
    local multi = ("`e(cmd)'" == "mlogit")
    if `multi' {
        local baseeq : word `e(ibaseout)' of `e(eqnames)'
        display as text "【`tag'】结局=`baseeq' | 基准类别"
    }
    local k = 0
    foreach nm of local cn {
        local ++k
        local eq : word `k' of `ce'
        if `multi' & "`eq'" == "`baseeq'" {
            continue
        }
        local en "`ename'"
        local dec = cond(`isratio', 2, 3)
        if `isratio' & !missing(`erow') {
            if `T'[`erow', `k'] == 0 {
                local en "系数"
                local dec 3
            }
        }
        local pre ""
        if `multi' {
            local pre "结局=`eq' | "
        }
        if "`eq'" == "inflate" {
            local pre "零膨胀方程 | "
        }
        _ubm_num b  `=`T'[1, `k']' `dec'
        _ubm_num lo `=`T'[5, `k']' `dec'
        _ubm_num hi `=`T'[6, `k']' `dec'
        _ubm_p   p  `=`T'[4, `k']'
        local ci "[`lo', `hi']"
        * 辅助参数：切点、lnalpha 与 alpha、删失模型的误差方差、Weibull 的形状参数，原样列出
        if substr("`eq'", 1, 1) == "/" | substr("`eq'", 1, 7) == "_diparm" {
            if "`brief'" != "1" {
                display as text "【`tag'-辅助参数】`nm' | 估计值=`b' | 95%CI=`ci'"
            }
            continue
        }
        if "`nm'" == "_cons" {
            if "`brief'" != "1" {
                display as text "【`tag'】`pre'常数项 | `en'=`b' | 95%CI=`ci' | p=`p'"
            }
            continue
        }
        if !strpos("`nm'", ".") {
            display as text "【`tag'】`pre'`nm' | `en'=`b' | 95%CI=`ci' | p=`p'"
            continue
        }
        local lev = substr("`nm'", 1, strpos("`nm'", ".") - 1)
        local vn  = substr("`nm'", strpos("`nm'", ".") + 1, .)
        local num = subinstr(subinstr("`lev'", "b", "", .), "o", "", .)
        if "`num'" == "" {
            display as text "【`tag'】`pre'`vn' | 被略去（共线性）"
            continue
        }
        local lab : label (`vn') `num'
        local lab = cond("`lab'" == "`num'", "", "（`lab'）")
        quietly count if `vn' == `num' & e(sample) & `flag' == 1
        if r(N) == 0 {
            display as text "【`tag'】`pre'`vn'=`num'`lab' | 无观测进入回归（该水平完全预测因变量，Stata 标为 empty）"
        }
        else if strpos("`lev'", "b") {
            display as text "【`tag'】`pre'`vn'=`num'`lab' | 参照组"
        }
        else if strpos("`lev'", "o") {
            display as text "【`tag'】`pre'`vn'=`num'`lab' | 被略去（完全预测或共线性）"
        }
        else {
            display as text "【`tag'】`pre'`vn'=`num'`lab' | `en'=`b' | 95%CI=`ci' | p=`p'"
        }
    }
end

capture program drop _ubm_fit
program define _ubm_fit
    * 模型整体的汇总行：样本量、拟合与整体检验；k 为模型编号（只有一个模型时为空），
    * N 为分析样本量，svy 为 1 时按抽样设计读取
    args k N svy
    local cmd "`e(cmd)'"
    local en = e(N)
    if "`svy'" == "1" {
        local en = e(N_sub)
    }
    local out "N=`en'"
    if "`svy'" == "1" {
        local out "`out' | 全部观测=`e(N)' | PSU=`e(N_psu)' | 分层=`e(N_strata)' | 设计自由度=`e(df_r)'"
    }
    if inlist("`cmd'", "cox", "weibull", "stcrreg") {
        local out "`out' | 研究对象=`e(N_sub)' | 失效事件=`e(N_fail)'"
        if "`cmd'" == "stcrreg" {
            local out "`out' | 竞争事件=`e(N_compete)'"
        }
    }
    if "`cmd'" == "tobit" {
        local out "`out' | 未删失=`e(N_unc)' | 左删失=`e(N_lc)' | 右删失=`e(N_rc)'"
    }
    if inlist("`cmd'", "zip", "zinb") {
        local out "`out' | 零值观测=`e(N_zero)'"
    }
    if "`cmd'" == "regress" {
        local out "`out' | R²=`=strtrim(string(e(r2), "%12.4f"))'"
        if !missing(e(r2_a)) {
            local out "`out' | 调整R²=`=strtrim(string(e(r2_a), "%12.4f"))'"
        }
    }
    else if "`cmd'" == "qreg" {
        local pr2 = 1 - e(sum_adev) / e(sum_rdev)
        local out "`out' | 分位数=`=strtrim(string(e(q), "%4.2f"))' | 伪R²=`=strtrim(string(`pr2', "%12.4f"))'"
    }
    else if !missing(e(r2_p)) & !inlist("`cmd'", "cox", "weibull", "stcrreg") {
        local out "`out' | 伪R²=`=strtrim(string(e(r2_p), "%12.4f"))'"
    }
    if !missing(e(F)) {
        * 抽样设计下为调整的 Wald 检验：分母自由度为设计自由度减检验的项数再加 1
        local df2 = e(df_r)
        if "`svy'" == "1" {
            local df2 = e(df_r) - e(df_m) + 1
        }
        local pf = Ftail(e(df_m), `df2', e(F))
        _ubm_p p `pf'
        _ubm_df d2 `df2'
        local out "`out' | F=`=strtrim(string(e(F), "%12.2f"))' | df=(`e(df_m)', `d2') | p=`p'"
    }
    else if !missing(e(chi2)) {
        local pc = chi2tail(e(df_m), e(chi2))
        _ubm_p p `pc'
        local out "`out' | `e(chi2type)' χ²=`=strtrim(string(e(chi2), "%12.2f"))' | df=`e(df_m)' | p=`p'"
    }
    display as text "【多变量-模型`k'】`out'"
    if "`cmd'" == "nbreg" {
        local al = strtrim(string(e(alpha), "%12.4f"))
        if "`e(chi2_c)'" != "" {
            local c2c = strtrim(string(e(chi2_c), "%12.2f"))
            local pa  = 0.5 * chi2tail(1, e(chi2_c))
            _ubm_p p `pa'
            display as text "【多变量-离散`k'】alpha=`al' | alpha=0 的似然比检验 chibar2(01)=`c2c' | p=`p'"
        }
        else {
            display as text "【多变量-离散`k'】alpha=`al' | 稳健、聚类标准误或抽样设计下不报告 alpha=0 的似然比检验"
        }
    }
    if `en' != `N' {
        display as error "注意：模型`k'实际使用 `en' 个观测，少于分析样本 `N'，多因某个分类水平完全预测了因变量；须在结果中写明"
    }
    if "`e(converged)'" == "0" {
        display as error "注意：模型`k'未收敛，结果不可用；须在结果中写明"
    }
end

capture program drop _ubm_mk
program define _ubm_mk
    * 把命令写法 pat 中的占位符换成实际内容，结果放进调用处的局部宏 mac：
    * @SP@ 抽样设计前缀，@Y@ 因变量，@X@ 自变量，@IF@ 样本条件，@VCE@ 标准误选项，
    * @INF@ 零膨胀方程的自变量
    args mac pat sp y x ifc vce inf
    local c : subinstr local pat "@SP@" "`sp'", all
    local c : subinstr local c "@Y@" "`y'", all
    local c : subinstr local c "@X@" "`x'", all
    local c : subinstr local c "@IF@" "`ifc'", all
    local c : subinstr local c "@VCE@" "`vce'", all
    local c : subinstr local c "@INF@" "`inf'", all
    local c = stritrim(strtrim(`"`c'"'))
    c_local `mac' `"`c'"'
end

capture program drop _ubm_test
program define _ubm_test
    * 联合检验的汇总行：tag 为标签，lbl 为显示名，terms 为检验的项，eqopt 为 equation() 选项
    args tag lbl terms eqopt
    quietly testparm `terms' `eqopt'
    local pv = r(p)
    _ubm_p p `pv'
    if !missing(r(F)) {
        local st = strtrim(string(r(F), "%12.2f"))
        local d1 = r(df)
        _ubm_df d2 `r(df_r)'
        display as text "【`tag'】`lbl' | F=`st' | df=(`d1', `d2') | p=`p'"
    }
    else {
        local st = strtrim(string(r(chi2), "%12.2f"))
        display as text "【`tag'】`lbl' | χ²=`st' | df=`r(df)' | p=`p'"
    }
end


* ====== （一）读入数据与检查 ======

* 【1-1】读入数据：报错 r(601) 说明文件不存在，先核对工作目录与路径
confirm file "`data'"
use "`data'", clear

* 【1-2】因变量类型与模型：model 留空时取该类型排在第一个的缺省模型
local okmodels_binary     "logit probit lpm mpoisson"
local okmodels_continuous "ols qreg tobit"
local okmodels_ordinal    "ologit oprobit"
local okmodels_nominal    "mlogit"
local okmodels_count      "nbreg poisson zinb zip"
local okmodels_survival   "cox weibull crreg"
if !inlist("`ytype'", "binary", "continuous", "ordinal", "nominal", "count", "survival") {
    display as error "ytype 只能是 binary continuous ordinal nominal count survival 之一"
    exit 198
}
if "`model'" == "" {
    local model : word 1 of `okmodels_`ytype''
}
local okm : list model in okmodels_`ytype'
if !`okm' {
    display as error "因变量类型 `ytype' 可选的模型为：`okmodels_`ytype''"
    exit 198
}
* 各模型回放结果的命令与效应名称
local replay `model'
local ename 系数
if "`model'" == "logit"    local replay logit, or
if "`model'" == "lpm"      local replay regress
if "`model'" == "mpoisson" local replay poisson, irr
if "`model'" == "ols"      local replay regress
if "`model'" == "ologit"   local replay ologit, or
if "`model'" == "mlogit"   local replay mlogit, rrr
if inlist("`model'", "nbreg", "poisson", "zinb", "zip") local replay `model', irr
if "`model'" == "cox"      local replay stcox
if "`model'" == "weibull"  local replay streg
if "`model'" == "crreg"    local replay stcrreg
if inlist("`model'", "logit", "ologit")          local ename OR
if "`model'" == "lpm"                            local ename 系数（概率差）
if "`model'" == "tobit"                          local ename 系数（潜变量）
if "`model'" == "mpoisson"                       local ename RR
if "`model'" == "mlogit"                         local ename RRR
if inlist("`model'", "nbreg", "poisson", "zinb", "zip") local ename IRR
if inlist("`model'", "cox", "weibull")           local ename HR
if "`model'" == "crreg"                          local ename SHR
* 双变量步骤中计数因变量的单变量回归：零膨胀模型改用对应的不含零膨胀的模型
local crude `model'
if "`model'" == "zip"  local crude poisson
if "`model'" == "zinb" local crude nbreg

* 【1-3】拆分分类自变量：xcatv 是变量名，xcati 是放进回归的写法（缺省 i.）
local xcatv ""
local xcati ""
foreach t of local xcat {
    if strpos("`t'", ".") {
        local xcatv `xcatv' `=substr("`t'", strpos("`t'", ".") + 1, .)'
        local xcati `xcati' `t'
    }
    else {
        local xcatv `xcatv' `t'
        local xcati `xcati' i.`t'
    }
}
local inflv ""
foreach t of local inflate {
    local inflv `inflv' `=substr("`t'", strpos("`t'", ".") + 1, .)'
}

* 【1-4】抽样设计与标准误：填了 wt、psu、strata 任一项即按抽样设计分析，标准误由设计决定；
*        否则 vce 留空为模型缺省，lpm 与 mpoisson 必须用稳健（或聚类）标准误
local svy = ("`wt'`psu'`strata'" != "")
local clustvar ""
local vceopt ""
if `svy' {
    if "`vce'" != "" {
        display as error "按抽样设计分析时，标准误由抽样设计决定，vce 须留空；按聚类计算的，把聚类变量填在 psu"
        exit 198
    }
    if "`model'" == "qreg" {
        display as error "qreg 不支持抽样设计（svy），请换用 ols，或不填 wt、psu、strata"
        exit 198
    }
    if "`ytype'" == "survival" {
        display as error "本模板的生存分析不支持抽样设计，请不填 wt、psu、strata"
        exit 198
    }
}
else if "`vce'" == "robust" {
    local vceopt "vce(robust)"
}
else if "`: word 1 of `vce''" == "cluster" & `: word count `vce'' == 2 {
    local clustvar : word 2 of `vce'
    local vceopt "vce(cluster `clustvar')"
}
else if "`vce'" != "" {
    display as error "vce 只能留空、写 robust，或写 cluster 加一个聚类变量名"
    exit 198
}
if "`model'" == "qreg" & "`clustvar'" != "" {
    display as error "qreg 不支持聚类标准误，vce 只能留空或写 robust"
    exit 198
}
if !`svy' & inlist("`model'", "lpm", "mpoisson") & "`vceopt'" == "" {
    local vceopt "vce(robust)"
}

* 【1-5】参数检查：至少一个自变量；同一变量只能归一类；因变量不作自变量；专用参数不混用
if "`xcont'`xcatv'" == "" {
    display as error "参数区至少要列出一个自变量"
    exit 198
}
local both : list xcont & xcatv
if "`both'" != "" {
    display as error "变量 `both' 同时列在连续与分类自变量中，只能归一类"
    exit 198
}
local yin1 : list y in xcont
local yin2 : list y in xcatv
if `yin1' | `yin2' {
    display as error "因变量 `y' 不能同时作自变量"
    exit 198
}
if !inlist("`unequal'", "0", "1") {
    display as error "unequal 只能是 0 或 1"
    exit 198
}
if "`ytype'" == "survival" & "`time'" == "" {
    display as error "survival 类型须在参数区填写生存时间变量 time"
    exit 198
}
if "`ytype'" != "survival" & "`time'" != "" {
    display as error "time 只用于 survival 类型"
    exit 198
}
if "`ytype'" != "count" & "`exposure'" != "" {
    display as error "exposure 只用于 count 类型"
    exit 198
}
if "`ytype'" != "nominal" & "`base'" != "" {
    display as error "base 只用于 nominal 类型"
    exit 198
}
if "`model'" == "crreg" {
    if "`compete'" == "" {
        display as error "crreg 须在参数区填写竞争事件的取值 compete"
        exit 198
    }
    confirm number `compete'
    if inlist(`compete', 0, 1) {
        display as error "compete 不能是 0 或 1：因变量中 0 为删失、1 为关注的失效事件"
        exit 198
    }
}
else if "`compete'" != "" {
    display as error "compete 只用于 crreg 模型"
    exit 198
}
if "`model'" == "qreg" {
    if "`quantile'" == "" {
        local quantile 0.5
    }
    confirm number `quantile'
    if !(`quantile' > 0 & `quantile' < 1) {
        display as error "quantile 须在 0 与 1 之间"
        exit 198
    }
}
else if "`quantile'" != "" {
    display as error "quantile 只用于 qreg 模型"
    exit 198
}
local llopt ""
local ulopt ""
if "`model'" == "tobit" {
    if "`ll'`ul'" == "" {
        display as error "tobit 须至少填写一个删失点：ll（左删失点）或 ul（右删失点）"
        exit 198
    }
    if "`ll'" != "" {
        confirm number `ll'
        local llopt "ll(`ll')"
    }
    if "`ul'" != "" {
        confirm number `ul'
        local ulopt "ul(`ul')"
    }
}
else if "`ll'`ul'" != "" {
    display as error "ll 与 ul 只用于 tobit 模型"
    exit 198
}
if !inlist("`model'", "zip", "zinb") & "`inflate'" != "" {
    display as error "inflate 只用于 zip、zinb 模型"
    exit 198
}
local expo = cond("`exposure'" == "", "", "exposure(`exposure')")
local eqopt = cond(inlist("`model'", "zip", "zinb"), ", equation(`y')", "")

* 【1-6】逐步加入的变量组：每个自变量恰好归入一组；模型 k 含第 1 至第 k 组
local K 1
local X1 `xcont' `xcati'
if "`blocks'" != "" {
    local K 0
    local rest "`blocks'"
    local allb ""
    local Xcum ""
    while "`rest'" != "" {
        gettoken blk rest : rest, parse("|")
        if "`blk'" == "|" {
            continue
        }
        local ++K
        local Bn`K' ""
        local Bq`K' ""
        local Bt`K' ""
        foreach nm of local blk {
            local inc : list nm in xcont
            local inv : list posof "`nm'" in xcatv
            if `inc' {
                local Bt`K' `Bt`K'' `nm'
                local Bq`K' `Bq`K'' `nm'
            }
            else if `inv' {
                local Bt`K' `Bt`K'' `: word `inv' of `xcati''
                local Bq`K' `Bq`K'' i.`nm'
            }
            else {
                display as error "blocks 中的 `nm' 不在 xcont 或 xcat 中；blocks 只写变量名，不写 i. 或 ib#."
                exit 198
            }
            local Bn`K' `Bn`K'' `nm'
        }
        local Xcum `Xcum' `Bt`K''
        local X`K' `Xcum'
        local allb `allb' `Bn`K''
    }
    local allx `xcont' `xcatv'
    local dupb : list dups allb
    local misb : list allx - allb
    if "`dupb'" != "" | "`misb'" != "" | `K' < 2 {
        display as error "blocks 须把全部自变量分成至少两组，每个变量恰好出现一次（重复：`dupb'；未归组：`misb'）"
        exit 198
    }
}

* 【1-7】变量须存在且为数值型：报错 r(111) 为变量不存在，r(7) 为字符串变量
confirm numeric variable `y' `xcont' `xcatv' `time' `exposure' `inflv' `wt'
if "`clustvar'" != "" {
    confirm variable `clustvar', exact
}
if "`psu'`strata'" != "" {
    confirm variable `psu' `strata', exact
}

* 【1-8】缺失情况：全部观测中各分析变量的缺失数（含 .a 等扩展缺失值）
misstable summarize `y' `xcont' `xcatv' `time' `exposure' `inflv' `wt', all

* 【1-9】生成分析样本标记：所列变量均非缺失的观测记为 1，其余记为 0
*        与 generate byte analysis = !missing(因变量, 各自变量, …) 等价
capture confirm variable `flag', exact
if !_rc {
    display as text "提示：数据中已有变量 `flag'，下面按本次的分析变量重新生成"
    drop `flag'
}
generate byte `flag' = 1
markout `flag' `y' `xcont' `xcatv' `time' `exposure' `inflv' `wt'
if "`clustvar'`psu'`strata'" != "" {
    markout `flag' `clustvar' `psu' `strata', strok
}
label variable `flag' "分析样本：所列分析变量均非缺失"

* 【1-10】全部观测数与分析样本量
count
count if `flag' == 1

* 【1-11】因变量的取值须与类型相符
quietly levelsof `y' if `flag' == 1, local(ylevs)
local nylev : word count `ylevs'
if "`ytype'" == "binary" | ("`ytype'" == "survival" & "`model'" != "crreg") {
    capture assert inlist(`y', 0, 1) if `flag' == 1
    if _rc {
        display as error "因变量 `y' 在分析样本中不只取 0 和 1；`ytype' 类型（`model'）须为 0/1 编码"
        exit 459
    }
    if `nylev' < 2 {
        display as error "因变量 `y' 在分析样本中只有一个取值，无法分组比较，也无法回归"
        exit 459
    }
}
if "`model'" == "crreg" {
    capture assert inlist(`y', 0, 1, `compete') if `flag' == 1
    if _rc {
        display as error "crreg 的因变量 `y' 只能取 0（删失）、1（关注的失效事件）与 `compete'（竞争事件）"
        exit 459
    }
    quietly count if `y' == 1 & `flag' == 1
    local nf = r(N)
    quietly count if `y' == `compete' & `flag' == 1
    if `nf' == 0 | r(N) == 0 {
        display as error "分析样本中须既有失效事件（`y' == 1），也有竞争事件（`y' == `compete'）"
        exit 459
    }
}
if inlist("`ytype'", "ordinal", "nominal", "count") {
    capture assert `y' == int(`y') if `flag' == 1
    if _rc {
        display as error "因变量 `y' 含小数；`ytype' 类型须为整数编码"
        exit 459
    }
}
if inlist("`ytype'", "ordinal", "nominal") & `nylev' < 3 {
    display as error "`ytype' 类型的因变量至少要有 3 个取值；只有两个取值时用 binary"
    exit 459
}
if "`ytype'" == "count" {
    capture assert `y' >= 0 if `flag' == 1
    if _rc {
        display as error "计数因变量 `y' 含负数"
        exit 459
    }
}
if inlist("`model'", "zip", "zinb") {
    quietly count if `y' == 0 & `flag' == 1
    if r(N) == 0 {
        display as error "零膨胀模型要求因变量有取 0 的观测"
        exit 459
    }
}
if "`ytype'" == "continuous" & `nylev' <= 5 {
    display as text "提示：连续因变量 `y' 只有 `nylev' 个取值，请确认是否应按分类变量处理"
}
if "`model'" == "tobit" {
    if "`ll'" != "" {
        quietly count if `y' < `ll' & `flag' == 1
        if r(N) > 0 {
            display as error "因变量 `y' 有小于左删失点 `ll' 的观测，须先核对删失点"
            exit 459
        }
    }
    if "`ul'" != "" {
        quietly count if `y' > `ul' & `flag' == 1
        if r(N) > 0 {
            display as error "因变量 `y' 有大于右删失点 `ul' 的观测，须先核对删失点"
            exit 459
        }
    }
}
if "`ytype'" == "survival" {
    capture assert `time' > 0 if `flag' == 1
    if _rc {
        display as error "生存时间 `time' 含小于或等于 0 的值，须先核对"
        exit 459
    }
}
if "`exposure'" != "" {
    capture assert `exposure' > 0 if `flag' == 1
    if _rc {
        display as error "暴露量 `exposure' 须大于 0"
        exit 459
    }
}
if "`wt'" != "" {
    capture assert `wt' > 0 if `flag' == 1
    if _rc {
        display as error "抽样权数 `wt' 须大于 0"
        exit 459
    }
}
if "`ytype'" == "nominal" {
    if "`base'" == "" {
        local base : word 1 of `ylevs'
    }
    local bin : list base in ylevs
    if !`bin' {
        display as error "基准类别 `base' 不在因变量 `y' 的取值中"
        exit 459
    }
}

* 【1-12】分类自变量须为非负整数编码（因子变量 i. 的要求）
foreach v of local xcatv {
    capture assert `v' == int(`v') & `v' >= 0 if `flag' == 1
    if _rc {
        display as error "分类变量 `v' 含负数或小数，须先重新编码"
        exit 459
    }
}

* 【1-13】仅当 savedata 为 1（用户允许修改数据文件）时，把标记变量存回数据文件
if `savedata' == 1 {
    save "`data'", replace
}

* 【1-14】生存数据：声明生存时间与失效变量；crreg 以因变量取 1 为关注的失效事件
if "`ytype'" == "survival" {
    if "`model'" == "crreg" {
        stset `time', failure(`y' == 1)
    }
    else {
        stset `time', failure(`y')
    }
}

* 【1-15】抽样调查数据：声明抽样设计；此后的估计命令用 subpop(标记变量) 限定分析样本，
*         不用 if，以免丢掉计算标准误所需的抽样设计信息
local sp ""
local ifs "if `flag' == 1"
local svydesign ""
if `svy' {
    local svydesign = cond("`psu'" == "", "_n", "`psu'")
    if "`wt'" != "" {
        local svydesign "`svydesign' [pweight = `wt']"
    }
    if "`strata'" != "" {
        local svydesign "`svydesign', strata(`strata')"
    }
    svyset `svydesign'
    local sp "svy, subpop(`flag'):"
    local ifs ""
}


* ====== （二）单变量分析 ======

* 连续变量：连续自变量，加上连续或计数因变量、生存时间；分类变量：分类自变量，加上其余类型的因变量
local ucont `xcont'
local ucat  `xcatv'
if inlist("`ytype'", "continuous", "count") {
    local ucont `y' `ucont'
}
if "`ytype'" == "survival" {
    local ucont `time' `ucont'
}
if inlist("`ytype'", "binary", "ordinal", "nominal", "survival") {
    local ucat `y' `ucat'
}

* 【2-1】连续变量：观测数、均值、标准差；抽样调查数据另给设计加权的均值
if "`ucont'" != "" {
    display _n as text "【描述统计】`ucont'"
    summarize `ucont' if `flag' == 1
    if `svy' {
        svy, subpop(`flag'): mean `ucont'
    }
}

* 【2-2】分类变量：频数与百分比；抽样调查数据另给设计加权的比例
foreach v of local ucat {
    display _n as text "【频数分布】`v'"
    tabulate `v' if `flag' == 1
    if `svy' {
        svy, subpop(`flag'): tabulate `v'
    }
}


* ====== （三）双变量分析：各自变量分别与因变量 ======
* 检验方法只由因变量类型、自变量类型与有无抽样设计决定，事先定好，不随结果改动

if !`svy' {

    * —— 二分类因变量：连续自变量做 t 检验（unequal 为 1 时不假定方差相等）
    local uneq = cond("`unequal'" == "1", "unequal", "")
    if "`ytype'" == "binary" {
        foreach v of local xcont {
            display _n as text "【t 检验】`v'（按 `y' 分组）"
            ttest `v' if `flag' == 1, by(`y') `uneq'
        }
    }

    * —— 连续因变量：连续自变量做 Pearson 相关；分类自变量两组做 t 检验，三组及以上做单因素方差分析
    if "`ytype'" == "continuous" {
        foreach v of local xcont {
            display _n as text "【Pearson 相关】`y' 与 `v'"
            pwcorr `y' `v' if `flag' == 1, sig obs
        }
        foreach v of local xcatv {
            quietly levelsof `v' if `flag' == 1, local(levs)
            if `: word count `levs'' == 2 {
                display _n as text "【t 检验】`y'（按 `v' 分组）"
                ttest `y' if `flag' == 1, by(`v') `uneq'
            }
            else {
                display _n as text "【单因素方差分析】`y'（按 `v' 分组）"
                oneway `y' `v' if `flag' == 1, tabulate
            }
        }
    }

    * —— 有序因变量、无暴露量的计数因变量：连续自变量做 Spearman 等级相关；
    *    分类自变量两组做 Wilcoxon 秩和检验，三组及以上做 Kruskal–Wallis 检验
    if "`ytype'" == "ordinal" | ("`ytype'" == "count" & "`exposure'" == "") {
        foreach v of local xcont {
            display _n as text "【Spearman 等级相关】`y' 与 `v'"
            spearman `y' `v' if `flag' == 1
        }
        foreach v of local xcatv {
            if "`ytype'" == "ordinal" {
                display _n as text "【分组分布】`y'（按 `v' 分组）"
                tabulate `v' `y' if `flag' == 1, row
            }
            else {
                display _n as text "【分组描述】`y'（按 `v' 分组）"
                tabstat `y' if `flag' == 1, by(`v') statistics(n mean sd p50)
            }
            quietly levelsof `v' if `flag' == 1, local(levs)
            if `: word count `levs'' == 2 {
                display _n as text "【Wilcoxon 秩和检验】`y'（按 `v' 分组）"
                ranksum `y' if `flag' == 1, by(`v')
            }
            else {
                display _n as text "【Kruskal–Wallis 检验】`y'（按 `v' 分组）"
                kwallis `y' if `flag' == 1, by(`v')
            }
        }
    }

    * —— 无序多分类因变量：连续自变量按因变量各类别做单因素方差分析
    if "`ytype'" == "nominal" {
        foreach v of local xcont {
            display _n as text "【单因素方差分析】`v'（按 `y' 分组）"
            oneway `v' `y' if `flag' == 1, tabulate
        }
    }

    * —— 二分类、无序多分类因变量：分类自变量做卡方检验；row 报告行百分比，expected 报告期望频数；
    *    有单元格期望频数小于 5 时，补做 Fisher 精确检验，以其双侧 p 值为准
    if inlist("`ytype'", "binary", "nominal") {
        foreach v of local xcatv {
            tempname O me
            display _n as text "【卡方检验】`v' × `y'"
            tabulate `v' `y' if `flag' == 1, row chi2 expected matcell(`O')
            mata: st_numscalar("`me'", min(rowsum(st_matrix("`O'")) * colsum(st_matrix("`O'")) / sum(st_matrix("`O'"))))
            display as text "最小期望频数 = " strtrim(string(scalar(`me'), "%12.2f"))
            if scalar(`me') < 5 {
                display as text "有单元格期望频数小于 5，补做 Fisher 精确检验"
                tabulate `v' `y' if `flag' == 1, exact
            }
        }
    }

    * —— 有暴露量的计数因变量：比较的是发生率，每个自变量单独进入计数模型，报告粗 IRR
    if "`ytype'" == "count" & "`exposure'" != "" {
        foreach t in `xcont' `xcati' {
            display _n as text "【单变量回归】`crude' `y' `t'（暴露量 `exposure'）"
            `crude' `y' `t' if `flag' == 1, irr `expo' `vceopt'
        }
    }

    * —— 生存因变量（cox、weibull）：连续自变量做单变量回归（粗 HR），分类自变量做 log-rank 检验
    if "`ytype'" == "survival" & "`model'" != "crreg" {
        foreach v of local xcont {
            display _n as text "【单变量生存回归】`v'"
            if "`model'" == "cox" {
                stcox `v' if `flag' == 1, `vceopt'
            }
            else {
                streg `v' if `flag' == 1, distribution(weibull) `vceopt'
            }
        }
        foreach v of local xcatv {
            display _n as text "【log-rank 检验】按 `v' 分组"
            sts test `v' if `flag' == 1
        }
    }

    * —— 竞争风险（crreg）：每个自变量单独进入竞争风险模型，报告粗 SHR
    if "`model'" == "crreg" {
        foreach t in `xcont' `xcati' {
            display _n as text "【单变量竞争风险回归】`t'"
            stcrreg `t' if `flag' == 1, compete(`y' == `compete') `vceopt'
        }
    }
}
else {

    * —— 抽样调查数据：检验按抽样设计计算，各命令用 subpop() 限定分析样本

    * 二分类、有序、无序多分类因变量的分类自变量：Rao–Scott 校正的卡方检验（设计校正 F）
    if inlist("`ytype'", "binary", "ordinal", "nominal") {
        foreach v of local xcatv {
            display _n as text "【Rao–Scott 卡方检验】`v' × `y'"
            svy, subpop(`flag'): tabulate `v' `y', row
        }
    }

    * 二分类、无序多分类因变量的连续自变量：自变量对因变量各类别回归的设计校正 F 检验
    if inlist("`ytype'", "binary", "nominal") {
        foreach v of local xcont {
            display _n as text "【设计校正 F 检验】`v'（按 `y' 分组）"
            svy, subpop(`flag'): regress `v' i.`y'
            testparm i.`y'
        }
    }

    * 连续因变量：连续自变量做单变量加权回归，分类自变量做设计校正 F 检验
    if "`ytype'" == "continuous" {
        foreach v of local xcont {
            display _n as text "【单变量加权回归】`y' 与 `v'"
            svy, subpop(`flag'): regress `y' `v'
        }
        foreach v of local xcatv {
            display _n as text "【设计校正 F 检验】`y'（按 `v' 分组）"
            svy, subpop(`flag'): regress `y' i.`v'
            testparm i.`v'
        }
    }

    * 有序因变量的连续自变量：单变量有序回归，报告粗效应
    if "`ytype'" == "ordinal" {
        foreach v of local xcont {
            display _n as text "【单变量回归】`model' `y' `v'"
            svy, subpop(`flag'): `model' `y' `v'
        }
    }

    * 计数因变量：每个自变量单独进入计数模型，报告粗 IRR
    if "`ytype'" == "count" {
        foreach t in `xcont' `xcati' {
            display _n as text "【单变量回归】`crude' `y' `t'"
            svy, subpop(`flag'): `crude' `y' `t', irr `expo'
        }
    }
}


* ====== （四）多变量分析 ======

* 【4-1】各模型的命令写法：@SP@ 抽样设计前缀，@Y@ 因变量，@X@ 自变量，@IF@ 样本条件，
*        @VCE@ 标准误选项，@INF@ 零膨胀方程的自变量；可选模块据此只改换一处重估模型
local qq = cond("`quantile'" == "", "0.5", "`quantile'")
local pat_logit    @SP@ logit @Y@ @X@ @IF@, or @VCE@
local pat_probit   @SP@ probit @Y@ @X@ @IF@, @VCE@
local pat_lpm      @SP@ regress @Y@ @X@ @IF@, @VCE@
local pat_mpoisson @SP@ poisson @Y@ @X@ @IF@, irr @VCE@
local pat_ols      @SP@ regress @Y@ @X@ @IF@, @VCE@
local pat_qreg     qreg @Y@ @X@ @IF@, quantile(`qq') @VCE@
local pat_tobit    @SP@ tobit @Y@ @X@ @IF@, `llopt' `ulopt' @VCE@
local pat_ologit   @SP@ ologit @Y@ @X@ @IF@, or @VCE@
local pat_oprobit  @SP@ oprobit @Y@ @X@ @IF@, @VCE@
local pat_mlogit   @SP@ mlogit @Y@ @X@ @IF@, rrr baseoutcome(`base') @VCE@
local pat_nbreg    @SP@ nbreg @Y@ @X@ @IF@, irr `expo' @VCE@
local pat_poisson  @SP@ poisson @Y@ @X@ @IF@, irr `expo' @VCE@
local pat_zinb     @SP@ zinb @Y@ @X@ @IF@, inflate(@INF@) irr `expo' @VCE@
local pat_zip      @SP@ zip @Y@ @X@ @IF@, inflate(@INF@) irr `expo' @VCE@
local pat_cox      stcox @X@ @IF@, @VCE@
local pat_weibull  streg @X@ @IF@, distribution(weibull) @VCE@
local pat_crreg    stcrreg @X@ @IF@, compete(@Y@ == `compete') @VCE@

* 【4-2】组成回归命令：分类自变量以 i. 进入，取值最小的类别为参照组（ib#. 可另指定）；
*        blocks 非空时，模型 1 只含第一组变量，此后每个模型加入下一组，最后一个为全模型；
*        各模型都在同一分析样本上估计
forvalues k = 1/`K' {
    local infl = cond("`inflate'" == "", "`X`k''", "`inflate'")
    _ubm_mk cmd`k' "`pat_`model''" "`sp'" "`y'" "`X`k''" "`ifs'" "`vceopt'" "`infl'"
}

* 【4-3】估计模型
forvalues k = 1/`K' {
    local kk = cond(`K' == 1, "", "-模型`k'")
    display _n as text "【多变量回归`kk'】`cmd`k''"
    `cmd`k''
    estimates store ubm_m`k'
}
estimates store ubm_main


* ====== （五）结果汇总 ======
* 以下只复述（一）至（四）的结果，供写入结果文件，不是新的分析

display _n as text "==================== 结果汇总 ===================="
quietly count
local N0 = r(N)
quietly count if `flag' == 1
local N = r(N)
local sted = cond(c(MP) == 1, " MP", cond(c(SE) == 1, " SE", ""))
display as text "【环境】Stata `=strtrim(string(c(stata_version), "%5.1f"))'`sted'"
display as text "【样本】全部观测=`N0' | 分析样本=`N'（`flag' == 1）| 未进入分析样本=`=`N0' - `N'' | 因变量类型=`ytype' | 模型=`model'"
if "`vceopt'" != "" {
    display as text "【样本】标准误：`vceopt'"
}
if `svy' {
    display as text "【样本】抽样设计：svyset `svydesign' | 估计命令用 subpop(`flag') 限定分析样本"
}
local misvars `y' `xcont' `xcatv' `time' `exposure' `inflv' `clustvar' `wt' `psu' `strata'
local misvars : list uniq misvars
foreach v of local misvars {
    quietly count if missing(`v')
    local pm = strtrim(string(100 * r(N) / `N0', "%12.1f"))
    display as text "【缺失】`v' | 缺失=`r(N)'（`pm'%）"
}

* 单变量：连续变量（抽样调查数据另给加权均值与加权标准差）
foreach v of local ucont {
    quietly summarize `v' if `flag' == 1
    local n  = r(N)
    local m  = strtrim(string(r(mean), "%12.2f"))
    local sd = strtrim(string(r(sd), "%12.2f"))
    local w ""
    if `svy' & "`wt'" != "" {
        quietly summarize `v' [aw = `wt'] if `flag' == 1
        local w " | 加权均值=`=strtrim(string(r(mean), "%12.2f"))' | 加权标准差=`=strtrim(string(r(sd), "%12.2f"))'"
    }
    display as text "【单变量-连续】`v' | N=`n' | 均值=`m' | 标准差=`sd'`w'"
}

* 单变量：分类变量（抽样调查数据另给加权百分比）
foreach v of local ucat {
    quietly levelsof `v' if `flag' == 1, local(levs)
    foreach l of local levs {
        quietly count if `v' == `l' & `flag' == 1
        local n   = r(N)
        local pct = strtrim(string(100 * `n' / `N', "%12.1f"))
        local w ""
        if `svy' & "`wt'" != "" {
            tempvar ind
            quietly generate byte `ind' = (`v' == `l') if `flag' == 1
            quietly summarize `ind' [aw = `wt']
            local w " | 加权百分比=`=strtrim(string(100 * r(mean), "%12.1f"))'"
            drop `ind'
        }
        local lab : label (`v') `l'
        local lab = cond("`lab'" == "`l'", "", "（`lab'）")
        display as text "【单变量-分类】`v'=`l'`lab' | 频数=`n' | 百分比=`pct'`w'"
    }
}

if !`svy' {

    * 双变量：二分类因变量的 t 检验
    if "`ytype'" == "binary" {
        foreach v of local xcont {
            _ubm_tsum `v' `y' `flag' `unequal'
        }
    }

    * 双变量：连续因变量
    if "`ytype'" == "continuous" {
        foreach v of local xcont {
            quietly correlate `y' `v' if `flag' == 1
            local r  = r(rho)
            local n  = r(N)
            local tt = `r' * sqrt((`n' - 2) / (1 - `r'^2))
            local pv = 2 * ttail(`n' - 2, abs(`tt'))
            _ubm_p p `pv'
            local rr = strtrim(string(`r', "%12.3f"))
            display as text "【双变量-Pearson】`y' 与 `v' | r=`rr' | N=`n' | p=`p'"
        }
        foreach v of local xcatv {
            quietly levelsof `v' if `flag' == 1, local(levs)
            if `: word count `levs'' == 2 {
                _ubm_tsum `y' `v' `flag' `unequal'
            }
            else {
                quietly oneway `y' `v' if `flag' == 1
                local F  = strtrim(string(r(F), "%12.2f"))
                local pv = Ftail(r(df_m), r(df_r), r(F))
                local d1 = r(df_m)
                local d2 = r(df_r)
                _ubm_p p `pv'
                display as text "【双变量-方差分析】`y' 按 `v' 分组 | F=`F' | df=(`d1', `d2') | p=`p'"
                _ubm_groups `y' `v' `flag'
            }
        }
    }

    * 双变量：有序因变量、无暴露量的计数因变量
    if "`ytype'" == "ordinal" | ("`ytype'" == "count" & "`exposure'" == "") {
        foreach v of local xcont {
            quietly spearman `y' `v' if `flag' == 1
            local rr = strtrim(string(r(rho), "%12.3f"))
            local n  = r(N)
            local pv = r(p)
            _ubm_p p `pv'
            display as text "【双变量-Spearman】`y' 与 `v' | rho=`rr' | N=`n' | p=`p'"
        }
        foreach v of local xcatv {
            quietly levelsof `v' if `flag' == 1, local(levs)
            if `: word count `levs'' == 2 {
                quietly ranksum `y' if `flag' == 1, by(`v')
                local z  = strtrim(string(r(z), "%12.2f"))
                local pv = 2 * normal(-abs(r(z)))
                _ubm_p p `pv'
                display as text "【双变量-秩和检验】`y' 按 `v' 分组 | z=`z' | p=`p'"
            }
            else {
                quietly kwallis `y' if `flag' == 1, by(`v')
                local c2 = strtrim(string(r(chi2_adj), "%12.2f"))
                local df = r(df)
                local pv = chi2tail(r(df), r(chi2_adj))
                _ubm_p p `pv'
                display as text "【双变量-Kruskal–Wallis】`y' 按 `v' 分组 | χ²（校正结）=`c2' | df=`df' | p=`p'"
            }
            _ubm_groups `y' `v' `flag'
        }
    }

    * 双变量：无序多分类因变量的方差分析
    if "`ytype'" == "nominal" {
        foreach v of local xcont {
            quietly oneway `v' `y' if `flag' == 1
            local F  = strtrim(string(r(F), "%12.2f"))
            local pv = Ftail(r(df_m), r(df_r), r(F))
            local d1 = r(df_m)
            local d2 = r(df_r)
            _ubm_p p `pv'
            display as text "【双变量-方差分析】`v' 按 `y' 分组 | F=`F' | df=(`d1', `d2') | p=`p'"
            _ubm_groups `v' `y' `flag'
        }
    }

    * 双变量：二分类、无序多分类因变量的卡方检验
    if inlist("`ytype'", "binary", "nominal") {
        foreach v of local xcatv {
            tempname O me
            quietly tabulate `v' `y' if `flag' == 1, chi2 matcell(`O')
            local chi2 = strtrim(string(r(chi2), "%12.2f"))
            local df   = (r(r) - 1) * (r(c) - 1)
            local pv   = r(p)
            _ubm_p p `pv'
            mata: st_numscalar("`me'", min(rowsum(st_matrix("`O'")) * colsum(st_matrix("`O'")) / sum(st_matrix("`O'"))))
            local mine = strtrim(string(scalar(`me'), "%12.2f"))
            if scalar(`me') < 5 {
                quietly tabulate `v' `y' if `flag' == 1, exact
                local pe = r(p_exact)
                _ubm_p pex `pe'
                local rep "Fisher 精确检验 p=`pex'"
            }
            else {
                local rep "卡方检验"
            }
            display as text "【双变量-卡方】`v' | χ²=`chi2' | df=`df' | p=`p' | 最小期望频数=`mine' | 报告：`rep'"
            _ubm_xtab `v' `y' `flag'
        }
    }

    * 双变量：有暴露量的计数因变量（粗 IRR）
    if "`ytype'" == "count" & "`exposure'" != "" {
        foreach t in `xcont' `xcati' {
            quietly `crude' `y' `t' if `flag' == 1, irr `expo' `vceopt'
            quietly `crude', irr
            tempname T
            matrix `T' = r(table)
            _ubm_effects "双变量-粗效应" "IRR" `T' `flag' 1
        }
    }

    * 双变量：生存因变量（cox、weibull）
    if "`ytype'" == "survival" & "`model'" != "crreg" {
        foreach v of local xcont {
            if "`model'" == "cox" {
                quietly stcox `v' if `flag' == 1, `vceopt'
                quietly stcox
            }
            else {
                quietly streg `v' if `flag' == 1, distribution(weibull) `vceopt'
                quietly streg
            }
            tempname T
            matrix `T' = r(table)
            _ubm_effects "双变量-粗效应" "HR" `T' `flag' 1
        }
        foreach v of local xcatv {
            quietly sts test `v' if `flag' == 1
            local c2 = strtrim(string(r(chi2), "%12.2f"))
            local df = r(df)
            local pv = chi2tail(r(df), r(chi2))
            _ubm_p p `pv'
            display as text "【双变量-log-rank】按 `v' 分组 | χ²=`c2' | df=`df' | p=`p'"
            quietly levelsof `v' if `flag' == 1, local(levs)
            foreach l of local levs {
                quietly count if `v' == `l' & `flag' == 1
                local nl = r(N)
                quietly count if `v' == `l' & `y' == 1 & `flag' == 1
                local ne = r(N)
                local lab : label (`v') `l'
                local lab = cond("`lab'" == "`l'", "", "（`lab'）")
                display as text "【双变量-log-rank-分组】`v'=`l'`lab' | 人数=`nl' | 失效事件=`ne'"
            }
        }
    }

    * 双变量：竞争风险（粗 SHR）
    if "`model'" == "crreg" {
        foreach t in `xcont' `xcati' {
            quietly stcrreg `t' if `flag' == 1, compete(`y' == `compete') `vceopt'
            quietly stcrreg
            tempname T
            matrix `T' = r(table)
            _ubm_effects "双变量-粗效应" "SHR" `T' `flag' 1
        }
    }
}
else {

    * 双变量（抽样调查数据）：分类自变量的 Rao–Scott 校正卡方检验
    if inlist("`ytype'", "binary", "ordinal", "nominal") {
        foreach v of local xcatv {
            quietly svy, subpop(`flag'): tabulate `v' `y'
            local F  = strtrim(string(e(F_Pear), "%12.2f"))
            local pv = e(p_Pear)
            local cu = strtrim(string(e(cun_Pear), "%12.2f"))
            _ubm_df d1 `e(df1_Pear)'
            _ubm_df d2 `e(df2_Pear)'
            _ubm_p p `pv'
            display as text "【双变量-RaoScott】`v' × `y' | F=`F' | df=(`d1', `d2') | p=`p' | 未校正χ²=`cu'"
            _ubm_xtab `v' `y' `flag' `wt'
        }
    }

    * 双变量（抽样调查数据）：二分类、无序多分类因变量的连续自变量
    if inlist("`ytype'", "binary", "nominal") {
        foreach v of local xcont {
            quietly svy, subpop(`flag'): regress `v' i.`y'
            quietly testparm i.`y'
            local F  = strtrim(string(r(F), "%12.2f"))
            local pv = r(p)
            local d1 = r(df)
            _ubm_df d2 `r(df_r)'
            _ubm_p p `pv'
            display as text "【双变量-设计F】`v' 按 `y' 分组 | F=`F' | df=(`d1', `d2') | p=`p'"
            _ubm_groups `v' `y' `flag' `wt'
        }
    }

    * 双变量（抽样调查数据）：连续因变量
    if "`ytype'" == "continuous" {
        local wexp = cond("`wt'" == "", "", "[aw = `wt']")
        local rlab = cond("`wt'" == "", "r", "加权r")
        foreach v of local xcont {
            quietly svy, subpop(`flag'): regress `y' `v'
            quietly regress
            tempname T
            matrix `T' = r(table)
            _ubm_num b  `=`T'[1, 1]' 3
            _ubm_num lo `=`T'[5, 1]' 3
            _ubm_num hi `=`T'[6, 1]' 3
            _ubm_p   p  `=`T'[4, 1]'
            quietly correlate `y' `v' `wexp' if `flag' == 1
            local rr = strtrim(string(r(rho), "%12.3f"))
            display as text "【双变量-加权回归】`y' 与 `v' | 系数=`b' | 95%CI=[`lo', `hi'] | p=`p' | `rlab'=`rr'"
        }
        foreach v of local xcatv {
            quietly svy, subpop(`flag'): regress `y' i.`v'
            quietly testparm i.`v'
            local F  = strtrim(string(r(F), "%12.2f"))
            local pv = r(p)
            local d1 = r(df)
            _ubm_df d2 `r(df_r)'
            _ubm_p p `pv'
            display as text "【双变量-设计F】`y' 按 `v' 分组 | F=`F' | df=(`d1', `d2') | p=`p'"
            _ubm_groups `y' `v' `flag' `wt'
        }
    }

    * 双变量（抽样调查数据）：有序因变量的连续自变量（粗效应）
    if "`ytype'" == "ordinal" {
        foreach v of local xcont {
            quietly svy, subpop(`flag'): `model' `y' `v'
            quietly `replay'
            tempname T
            matrix `T' = r(table)
            _ubm_effects "双变量-粗效应" "`ename'" `T' `flag' 1
        }
    }

    * 双变量（抽样调查数据）：计数因变量（粗 IRR）
    if "`ytype'" == "count" {
        foreach t in `xcont' `xcati' {
            quietly svy, subpop(`flag'): `crude' `y' `t', irr `expo'
            quietly `crude', irr
            tempname T
            matrix `T' = r(table)
            _ubm_effects "双变量-粗效应" "IRR" `T' `flag' 1
        }
    }
}

* 多变量：各模型的拟合与效应；分组加入变量时，另列每个模型新增变量的联合检验
forvalues k = 1/`K' {
    local kk = cond(`K' == 1, "", "`k'")
    estimates restore ubm_m`k'
    quietly `replay'
    tempname T
    matrix `T' = r(table)
    _ubm_fit "`kk'" `N' `svy'
    _ubm_effects "多变量-效应`kk'" "`ename'" `T' `flag'
    if `k' > 1 {
        _ubm_test "多变量-增量检验" "模型`k' 新增 `Bn`k''" "`Bq`k''" "`eqopt'"
    }
}

* 多变量：三类及以上的分类自变量，在全模型中检验其各水平的系数是否同时为 0
estimates restore ubm_main
foreach v of local xcatv {
    quietly levelsof `v' if `flag' == 1, local(levs)
    if `: word count `levs'' >= 3 {
        _ubm_test "多变量-联合检验" "`v'" "i.`v'" "`eqopt'"
    }
}
display as text "==================== 汇总结束 ===================="
