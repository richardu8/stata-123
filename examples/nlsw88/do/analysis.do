* =============================================================
* 单变量、双变量、多变量分析
* 日期：2026-11-01
* 用途：对二分类因变量做描述统计、t 检验与卡方检验、logistic 回归（报告 OR）
* 输入：参数区 data 指定的数据文件
* 输出：运行日志（Stata 连接器自动保存；命令行批处理在当前目录生成同名 .log）
* 来源：stata-uni-bi-multi 技能的模板，只改参数区，其余各段不改
* 说明：在项目根目录运行，路径相对于项目根目录；本文件不写 log using；
*       分析样本用标记变量限定，各分析命令都带 if 条件，不删除任何观测
* =============================================================

clear all
set more off
set varabbrev off      // 变量名须写全，不按缩写匹配
set linesize 255       // 结果汇总每条占一行，不折行

* ======================= 参数区：只改这一段 =======================
local data     "inputs/nlsw88.dta"            // 数据文件（例：inputs/clhls2021_analysis.dta）
local y        union                          // 因变量，只取 0 和 1（例：disabled）
local xcont    age grade wage                 // 连续自变量，可留空（例：age edu）
local xcat     race married collgrad south    // 分类自变量，可留空；改参照组写 ib#.变量名（例：female urban a51）
local flag     analysis                       // 分析样本标记变量名
local savedata 0                              // 1＝把标记变量存回数据文件；0＝不改数据文件
* ================================================================


* ====== （一）读入数据与检查 ======

* 【1-1】读入数据：报错 r(601) 说明文件不存在，先核对工作目录与路径
confirm file "`data'"
use "`data'", clear

* 【1-2】拆分分类变量：xcatv 是变量名，xcati 是放进回归的因子写法（默认 i.）
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

* 【1-3】参数检查：至少一个自变量；同一变量只能归一类；因变量不作自变量
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

* 【1-4】变量须存在且为数值型：报错 r(111) 为变量不存在，r(7) 为字符串变量
confirm numeric variable `y' `xcont' `xcatv'

* 【1-5】生成分析样本标记：因变量与全部自变量均非缺失的观测记为 1，其余记为 0
*        与 generate byte analysis = !missing(因变量, 各自变量) 等价
capture confirm variable `flag', exact
if !_rc {
    display as text "提示：数据中已有变量 `flag'，下面按本次的分析变量重新生成"
    drop `flag'
}
generate byte `flag' = 1
markout `flag' `y' `xcont' `xcatv'
label variable `flag' "分析样本：`y' `xcont' `xcatv' 均非缺失"

* 【1-6】全部观测数与分析样本量
count
count if `flag' == 1

* 【1-7】因变量须只取 0 和 1，且两类都有观测
capture assert inlist(`y', 0, 1) if `flag' == 1
if _rc {
    display as error "因变量 `y' 在分析样本中不只取 0 和 1；本模板只适用于二分类因变量"
    exit 459
}
quietly count if `y' == 1 & `flag' == 1
local n_y1 = r(N)
quietly count if `y' == 0 & `flag' == 1
if r(N) == 0 | `n_y1' == 0 {
    display as error "因变量 `y' 在分析样本中只有一个取值，无法分组比较，也无法回归"
    exit 459
}

* 【1-8】分类自变量须为非负整数编码（因子变量 i. 的要求）
foreach v of local xcatv {
    capture assert `v' == int(`v') & `v' >= 0 if `flag' == 1
    if _rc {
        display as error "分类变量 `v' 含负数或小数，须先重新编码"
        exit 459
    }
}

* 【1-9】仅当 savedata 为 1（用户允许修改数据文件）时，把标记变量存回数据文件
if `savedata' == 1 {
    save "`data'", replace
}


* ====== （二）单变量分析 ======

* 【2-1】连续变量：观测数、均值、标准差
if "`xcont'" != "" {
    display _n as text "【描述统计】`xcont'"
    summarize `xcont' if `flag' == 1
}

* 【2-2】分类变量（含因变量）：频数与百分比
foreach v in `y' `xcatv' {
    display _n as text "【频数分布】`v'"
    tabulate `v' if `flag' == 1
}


* ====== （三）双变量分析 ======

* 【3-1】连续自变量：按因变量分两组做 t 检验（两组方差相等）
foreach v of local xcont {
    display _n as text "【t 检验】`v'（按 `y' 分组）"
    ttest `v' if `flag' == 1, by(`y')
}

* 【3-2】分类自变量：卡方检验；row 报告行百分比，expected 报告期望频数；
*        有单元格期望频数小于 5 时，补做 Fisher 精确检验，以其双侧 p 值为准
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


* ====== （四）多变量分析 ======

* 【4-1】二分类 logistic 回归：or 选项报告 OR 及其 95% 置信区间；
*        分类自变量以 i. 进入，取值最小的类别为参照组（ib#. 可另指定）
display _n as text "【logistic 回归】logit `y' `xcont' `xcati' if `flag' == 1, or"
logit `y' `xcont' `xcati' if `flag' == 1, or
estimates store ubm_logit


* ====== （五）结果汇总 ======
* 以下只复述（一）至（四）的结果，供写入结果文件，不是新的分析

display _n as text "==================== 结果汇总 ===================="
quietly count
local N0 = r(N)
quietly count if `flag' == 1
local N = r(N)
display as text "【样本】全部观测=`N0' | 分析样本=`N'（`flag' == 1）"

* 单变量：连续变量
foreach v of local xcont {
    quietly summarize `v' if `flag' == 1
    local n  = r(N)
    local m  = strtrim(string(r(mean), "%12.2f"))
    local sd = strtrim(string(r(sd), "%12.2f"))
    display as text "【单变量-连续】`v' | N=`n' | 均值=`m' | 标准差=`sd'"
}

* 单变量：分类变量（含因变量）
foreach v in `y' `xcatv' {
    quietly levelsof `v' if `flag' == 1, local(levs)
    foreach l of local levs {
        quietly count if `v' == `l' & `flag' == 1
        local n   = r(N)
        local pct = strtrim(string(100 * `n' / `N', "%12.1f"))
        local lab : label (`v') `l'
        local lab = cond("`lab'" == "`l'", "", "（`lab'）")
        display as text "【单变量-分类】`v'=`l'`lab' | 频数=`n' | 百分比=`pct'"
    }
}

* 双变量：t 检验（第 1 组为 `y'=0，第 2 组为 `y'=1）
foreach v of local xcont {
    quietly ttest `v' if `flag' == 1, by(`y')
    local n0 = r(N_1)
    local n1 = r(N_2)
    local m0 = strtrim(string(r(mu_1), "%12.2f"))
    local s0 = strtrim(string(r(sd_1), "%12.2f"))
    local m1 = strtrim(string(r(mu_2), "%12.2f"))
    local s1 = strtrim(string(r(sd_2), "%12.2f"))
    local t  = strtrim(string(r(t), "%12.2f"))
    local df = r(df_t)
    local p  = cond(r(p) < 0.001, "<0.001", strtrim(string(r(p), "%12.3f")))
    display as text "【双变量-t检验】`v' | `y'=0：N=`n0' 均值=`m0' 标准差=`s0' | `y'=1：N=`n1' 均值=`m1' 标准差=`s1' | t=`t' | df=`df' | p=`p'"
}

* 双变量：卡方检验
foreach v of local xcatv {
    tempname O me
    quietly tabulate `v' `y' if `flag' == 1, chi2 matcell(`O')
    local chi2 = strtrim(string(r(chi2), "%12.2f"))
    local df   = (r(r) - 1) * (r(c) - 1)
    local p    = cond(r(p) < 0.001, "<0.001", strtrim(string(r(p), "%12.3f")))
    mata: st_numscalar("`me'", min(rowsum(st_matrix("`O'")) * colsum(st_matrix("`O'")) / sum(st_matrix("`O'"))))
    local mine = strtrim(string(scalar(`me'), "%12.2f"))
    if scalar(`me') < 5 {
        quietly tabulate `v' `y' if `flag' == 1, exact
        local pex = cond(r(p_exact) < 0.001, "<0.001", strtrim(string(r(p_exact), "%12.3f")))
        local rep "Fisher 精确检验 p=`pex'"
    }
    else {
        local rep "卡方检验"
    }
    display as text "【双变量-卡方】`v' | χ²=`chi2' | df=`df' | p=`p' | 最小期望频数=`mine' | 报告：`rep'"
    quietly levelsof `v' if `flag' == 1, local(levs)
    foreach l of local levs {
        quietly count if `v' == `l' & `flag' == 1
        local nl = r(N)
        quietly count if `v' == `l' & `y' == 1 & `flag' == 1
        local nl1 = r(N)
        local pct = strtrim(string(100 * `nl1' / `nl', "%12.1f"))
        local lab : label (`v') `l'
        local lab = cond("`lab'" == "`l'", "", "（`lab'）")
        display as text "【双变量-卡方-分组】`v'=`l'`lab' | 合计=`nl' | `y'=1 的频数=`nl1' | 行百分比=`pct'"
    }
}

* 多变量：logistic 回归
estimates restore ubm_logit
quietly logit, or
tempname T
matrix `T' = r(table)
local en = e(N)
local r2 = strtrim(string(e(r2_p), "%12.4f"))
local lr = strtrim(string(e(chi2), "%12.2f"))
local dm = e(df_m)
local pm = cond(e(p) < 0.001, "<0.001", strtrim(string(e(p), "%12.3f")))
display as text "【多变量-模型】N=`en' | 伪R²=`r2' | LR χ²=`lr' | df=`dm' | p=`pm'"
if `en' != `N' {
    display as error "注意：logit 实际使用 `en' 个观测，少于分析样本 `N'，多因某个分类水平完全预测了因变量；须在结果中写明"
}
local cn : colnames `T'
local k = 0
foreach nm of local cn {
    local ++k
    * OR 与置信区间：一般保留两位小数；小于 0.01 时保留两位有效数字，不小于 10000 时用科学计数
    foreach s in or lo hi {
        local row = cond("`s'" == "or", 1, cond("`s'" == "lo", 5, 6))
        local x = `T'[`row', `k']
        if missing(`x') {
            local `s' "."
        }
        else if `x' > 0 & `x' < 0.01 {
            local d = ceil(-log10(`x')) + 1
            local `s' = strtrim(string(`x', "%20.`d'f"))
        }
        else if `x' >= 10000 {
            local `s' = strtrim(string(`x', "%12.2e"))
        }
        else {
            local `s' = strtrim(string(`x', "%12.2f"))
        }
    }
    local pv = `T'[4, `k']
    local p  = cond(`pv' < 0.001, "<0.001", strtrim(string(`pv', "%12.3f")))
    if "`nm'" == "_cons" {
        display as text "【多变量-OR】常数项 | OR=`or' | 95%CI=`lo'–`hi' | p=`p'"
        continue
    }
    if !strpos("`nm'", ".") {
        display as text "【多变量-OR】`nm' | OR=`or' | 95%CI=`lo'–`hi' | p=`p'"
        continue
    }
    local lev = substr("`nm'", 1, strpos("`nm'", ".") - 1)
    local vn  = substr("`nm'", strpos("`nm'", ".") + 1, .)
    local num = subinstr(subinstr("`lev'", "b", "", .), "o", "", .)
    if "`num'" == "" {
        display as text "【多变量-OR】`vn' | 被略去（共线性）"
        continue
    }
    local lab : label (`vn') `num'
    local lab = cond("`lab'" == "`num'", "", "（`lab'）")
    quietly count if `vn' == `num' & e(sample)
    if r(N) == 0 {
        display as text "【多变量-OR】`vn'=`num'`lab' | 无观测进入回归（该水平完全预测因变量，Stata 标为 empty）"
        continue
    }
    if strpos("`lev'", "b") {
        display as text "【多变量-OR】`vn'=`num'`lab' | 参照组"
    }
    else if strpos("`lev'", "o") {
        display as text "【多变量-OR】`vn'=`num'`lab' | 被略去（完全预测或共线性）"
    }
    else {
        display as text "【多变量-OR】`vn'=`num'`lab' | OR=`or' | 95%CI=`lo'–`hi' | p=`p'"
    }
}
display as text "==================== 汇总结束 ===================="
