* =============================================================
* 单变量、双变量、多变量分析
* 日期：YYYY-MM-DD
* 用途：按因变量类型做描述统计、双变量检验与多变量回归
* 输入：参数区 data 指定的数据文件
* 输出：运行日志（Stata 连接器自动保存；命令行批处理在当前目录生成同名 .log）
* 来源：stata-uni-bi-multi 技能 1.1.0 的模板，只改参数区，其余各段不改
* 说明：在项目根目录运行，路径相对于项目根目录；本文件不写 log using；
*       分析样本用标记变量限定，各分析命令都带 if 条件，不删除任何观测
* =============================================================

clear all
set more off
set varabbrev off      // 变量名须写全，不按缩写匹配
set linesize 255       // 结果汇总每条占一行，不折行

* ======================= 参数区：只改这一段 =======================
local data     "inputs/your_data.dta"   // 数据文件（例：inputs/clhls2021_analysis.dta）
local ytype    binary                   // 因变量类型：binary continuous ordinal nominal count survival
local model                             // 模型；留空用该类型的缺省模型（见下方对照）
local y        YOUR_DV                  // 因变量；survival 时为失效指示变量 0/1（例：disabled）
local xcont    YOUR_CONTINUOUS_VARS     // 连续自变量，可留空（例：age edu）
local xcat     YOUR_CATEGORICAL_VARS    // 分类自变量，可留空；改参照组写 ib#.变量名（例：female urban a51）
local time                              // 仅 survival：生存时间变量
local exposure                          // 仅 count：暴露量变量（如人年），可留空
local base                              // 仅 nominal：基准类别的取值，留空用最小取值
local vce                               // 标准误：留空为模型缺省；robust；cluster 聚类变量名
local flag     analysis                 // 分析样本标记变量名
local savedata 0                        // 1＝把标记变量存回数据文件；0＝不改数据文件
* ----------------------------------------------------------------
* 因变量类型与可选模型（排在第一个的是缺省模型）：
*   binary      logit（OR）  probit  lpm（线性概率模型）  mpoisson（修正泊松，RR）
*   continuous  ols
*   ordinal     ologit（OR）  oprobit
*   nominal     mlogit（RRR）
*   count       nbreg（IRR）  poisson（IRR）
*   survival    cox（HR）
* ================================================================


* ====== 辅助程序：只用于结果汇总的数字格式与逐项列出，不做分析 ======

capture program drop _ubm_num
program define _ubm_num
    * 效应值格式：比值类保留两位小数、系数类保留三位（dec）；绝对值小于 10^(-dec) 时
    * 保留两位有效数字；不小于 10000 用科学计数
    args mac x dec
    if "`dec'" == "" local dec 2
    if missing(`x') {
        c_local `mac' "."
    }
    else if `x' != 0 & abs(`x') < 10^(-`dec') {
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

capture program drop _ubm_tsum
program define _ubm_tsum
    * t 检验的汇总行：outvar 按 grpvar 分两组
    args outvar grpvar flag
    quietly ttest `outvar' if `flag' == 1, by(`grpvar')
    local n1 = r(N_1)
    local n2 = r(N_2)
    local m1 = strtrim(string(r(mu_1), "%12.2f"))
    local s1 = strtrim(string(r(sd_1), "%12.2f"))
    local m2 = strtrim(string(r(mu_2), "%12.2f"))
    local s2 = strtrim(string(r(sd_2), "%12.2f"))
    local t  = strtrim(string(r(t), "%12.2f"))
    local df = r(df_t)
    local pv = r(p)
    _ubm_p p `pv'
    quietly levelsof `grpvar' if `flag' == 1, local(g)
    local g1 : word 1 of `g'
    local g2 : word 2 of `g'
    display as text "【双变量-t检验】`outvar' 按 `grpvar' 分组 | `grpvar'=`g1'：N=`n1' 均值=`m1' 标准差=`s1' | `grpvar'=`g2'：N=`n2' 均值=`m2' 标准差=`s2' | t=`t' | df=`df' | p=`p'"
end

capture program drop _ubm_groups
program define _ubm_groups
    * 分组描述的汇总行：outvar 在 grpvar 各组的观测数、均值、标准差、中位数
    args outvar grpvar flag
    quietly levelsof `grpvar' if `flag' == 1, local(levs)
    foreach l of local levs {
        quietly summarize `outvar' if `grpvar' == `l' & `flag' == 1, detail
        local n  = r(N)
        local m  = strtrim(string(r(mean), "%12.2f"))
        local sd = strtrim(string(r(sd), "%12.2f"))
        local md = strtrim(string(r(p50), "%12.2f"))
        local lab : label (`grpvar') `l'
        local lab = cond("`lab'" == "`l'", "", "（`lab'）")
        display as text "【双变量-分组】`outvar' | `grpvar'=`l'`lab' | N=`n' | 均值=`m' | 标准差=`sd' | 中位数=`md'"
    }
end

capture program drop _ubm_effects
program define _ubm_effects
    * 逐项列出估计结果：tag 为汇总行标签，ename 为效应名称，T 为 r(table) 的副本；
    * brief 为 1 时只列自变量（单变量回归的粗效应用），不列常数项与辅助参数
    args tag ename T brief
    local dec = cond(strpos("`ename'", "系数") == 1, 3, 2)
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
        local pre = cond(`multi', "结局=`eq' | ", "")
        _ubm_num b  `=`T'[1, `k']' `dec'
        _ubm_num lo `=`T'[5, `k']' `dec'
        _ubm_num hi `=`T'[6, `k']' `dec'
        _ubm_p   p  `=`T'[4, `k']'
        local ci "[`lo', `hi']"
        * 辅助参数：有序模型的切点、负二项模型的 lnalpha 与 alpha，原样列出
        if substr("`eq'", 1, 1) == "/" | substr("`eq'", 1, 7) == "_diparm" {
            if "`brief'" != "1" {
                display as text "【`tag'-辅助参数】`nm' | 估计值=`b' | 95%CI=`ci'"
            }
            continue
        }
        if "`nm'" == "_cons" {
            if "`brief'" != "1" {
                display as text "【`tag'】`pre'常数项 | `ename'=`b' | 95%CI=`ci' | p=`p'"
            }
            continue
        }
        if !strpos("`nm'", ".") {
            display as text "【`tag'】`pre'`nm' | `ename'=`b' | 95%CI=`ci' | p=`p'"
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
        quietly count if `vn' == `num' & e(sample)
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
            display as text "【`tag'】`pre'`vn'=`num'`lab' | `ename'=`b' | 95%CI=`ci' | p=`p'"
        }
    }
end

capture program drop _ubm_fit
program define _ubm_fit
    * 模型整体的汇总行：样本量、拟合与整体检验
    args N
    local en = e(N)
    if "`e(cmd)'" == "regress" {
        local r2  = strtrim(string(e(r2), "%12.4f"))
        local r2a = strtrim(string(e(r2_a), "%12.4f"))
        local F   = strtrim(string(e(F), "%12.2f"))
        local pf  = Ftail(e(df_m), e(df_r), e(F))
        _ubm_p p `pf'
        display as text "【多变量-模型】N=`en' | R²=`r2' | 调整R²=`r2a' | F=`F' | df=(`e(df_m)', `e(df_r)') | p=`p'"
    }
    else if "`e(cmd)'" == "cox" {
        local c2 = strtrim(string(e(chi2), "%12.2f"))
        local pc = chi2tail(e(df_m), e(chi2))
        _ubm_p p `pc'
        display as text "【多变量-模型】N=`en' | 研究对象=`e(N_sub)' | 失效事件=`e(N_fail)' | `e(chi2type)' χ²=`c2' | df=`e(df_m)' | p=`p'"
    }
    else {
        local r2 = strtrim(string(e(r2_p), "%12.4f"))
        local c2 = strtrim(string(e(chi2), "%12.2f"))
        local pc = e(p)
        _ubm_p p `pc'
        display as text "【多变量-模型】N=`en' | 伪R²=`r2' | `e(chi2type)' χ²=`c2' | df=`e(df_m)' | p=`p'"
    }
    if "`e(cmd)'" == "nbreg" {
        local al = strtrim(string(e(alpha), "%12.4f"))
        if "`e(chi2_c)'" != "" {
            local c2c = strtrim(string(e(chi2_c), "%12.2f"))
            local pa  = 0.5 * chi2tail(1, e(chi2_c))
            _ubm_p p `pa'
            display as text "【多变量-离散】alpha=`al' | alpha=0 的似然比检验 chibar2(01)=`c2c' | p=`p'"
        }
        else {
            display as text "【多变量-离散】alpha=`al' | 稳健或聚类标准误下不报告 alpha=0 的似然比检验"
        }
    }
    if `en' != `N' {
        display as error "注意：模型实际使用 `en' 个观测，少于分析样本 `N'，多因某个分类水平完全预测了因变量；须在结果中写明"
    }
    if "`e(converged)'" == "0" {
        display as error "注意：模型未收敛，结果不可用；须在结果中写明"
    }
end


* ====== （一）读入数据与检查 ======

* 【1-1】读入数据：报错 r(601) 说明文件不存在，先核对工作目录与路径
confirm file "`data'"
use "`data'", clear

* 【1-2】因变量类型与模型：model 留空时取该类型排在第一个的缺省模型
local okmodels_binary     "logit probit lpm mpoisson"
local okmodels_continuous "ols"
local okmodels_ordinal    "ologit oprobit"
local okmodels_nominal    "mlogit"
local okmodels_count      "nbreg poisson"
local okmodels_survival   "cox"
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

* 【1-4】标准误：留空为模型缺省；lpm 与 mpoisson 必须用稳健（或聚类）标准误
local clustvar ""
local vceopt ""
if "`vce'" == "robust" {
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
if inlist("`model'", "lpm", "mpoisson") & "`vceopt'" == "" {
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

* 【1-6】变量须存在且为数值型：报错 r(111) 为变量不存在，r(7) 为字符串变量
confirm numeric variable `y' `xcont' `xcatv' `time' `exposure'
if "`clustvar'" != "" {
    confirm variable `clustvar', exact
}

* 【1-7】生成分析样本标记：所列变量均非缺失的观测记为 1，其余记为 0
*        与 generate byte analysis = !missing(因变量, 各自变量, …) 等价
capture confirm variable `flag', exact
if !_rc {
    display as text "提示：数据中已有变量 `flag'，下面按本次的分析变量重新生成"
    drop `flag'
}
generate byte `flag' = 1
markout `flag' `y' `xcont' `xcatv' `time' `exposure'
if "`clustvar'" != "" {
    markout `flag' `clustvar', strok
}
label variable `flag' "分析样本：所列分析变量均非缺失"

* 【1-8】全部观测数与分析样本量
count
count if `flag' == 1

* 【1-9】因变量的取值须与类型相符
quietly levelsof `y' if `flag' == 1, local(ylevs)
local nylev : word count `ylevs'
if inlist("`ytype'", "binary", "survival") {
    capture assert inlist(`y', 0, 1) if `flag' == 1
    if _rc {
        display as error "因变量 `y' 在分析样本中不只取 0 和 1；`ytype' 类型须为 0/1 编码"
        exit 459
    }
    if `nylev' < 2 {
        display as error "因变量 `y' 在分析样本中只有一个取值，无法分组比较，也无法回归"
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
if "`ytype'" == "continuous" & `nylev' <= 5 {
    display as text "提示：连续因变量 `y' 只有 `nylev' 个取值，请确认是否应按分类变量处理"
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

* 【1-10】分类自变量须为非负整数编码（因子变量 i. 的要求）
foreach v of local xcatv {
    capture assert `v' == int(`v') & `v' >= 0 if `flag' == 1
    if _rc {
        display as error "分类变量 `v' 含负数或小数，须先重新编码"
        exit 459
    }
}

* 【1-11】仅当 savedata 为 1（用户允许修改数据文件）时，把标记变量存回数据文件
if `savedata' == 1 {
    save "`data'", replace
}

* 【1-12】生存数据：声明生存时间与失效变量
if "`ytype'" == "survival" {
    stset `time', failure(`y')
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

* 【2-1】连续变量：观测数、均值、标准差
if "`ucont'" != "" {
    display _n as text "【描述统计】`ucont'"
    summarize `ucont' if `flag' == 1
}

* 【2-2】分类变量：频数与百分比
foreach v of local ucat {
    display _n as text "【频数分布】`v'"
    tabulate `v' if `flag' == 1
}


* ====== （三）双变量分析：各自变量分别与因变量 ======
* 检验方法只由因变量类型与自变量类型决定，事先定好，不随结果改动

* —— 二分类因变量：连续自变量做 t 检验，分类自变量做卡方检验
if "`ytype'" == "binary" {
    foreach v of local xcont {
        display _n as text "【t 检验】`v'（按 `y' 分组，两组方差相等）"
        ttest `v' if `flag' == 1, by(`y')
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
            display _n as text "【t 检验】`y'（按 `v' 分组，两组方差相等）"
            ttest `y' if `flag' == 1, by(`v')
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

* —— 有暴露量的计数因变量：比较的是发生率，每个自变量单独进入同一计数模型，报告粗 IRR
if "`ytype'" == "count" & "`exposure'" != "" {
    foreach t in `xcont' `xcati' {
        display _n as text "【单变量回归】`model' `y' `t'（暴露量 `exposure'）"
        `model' `y' `t' if `flag' == 1, irr exposure(`exposure') `vceopt'
    }
}

* —— 生存因变量：连续自变量做单变量 Cox 回归（粗 HR），分类自变量做 log-rank 检验
if "`ytype'" == "survival" {
    foreach v of local xcont {
        display _n as text "【单变量 Cox 回归】`v'"
        stcox `v' if `flag' == 1, `vceopt'
    }
    foreach v of local xcatv {
        display _n as text "【log-rank 检验】按 `v' 分组"
        sts test `v' if `flag' == 1
    }
}


* ====== （四）多变量分析 ======

* 【4-1】按模型组成回归命令：分类自变量以 i. 进入，取值最小的类别为参照组（ib#. 可另指定）
local X `xcont' `xcati'
if "`model'" == "logit" {
    local cmd logit `y' `X' if `flag' == 1, or `vceopt'
    local replay logit, or
    local ename OR
}
if "`model'" == "probit" {
    local cmd probit `y' `X' if `flag' == 1, `vceopt'
    local replay probit
    local ename 系数
}
if "`model'" == "lpm" {
    local cmd regress `y' `X' if `flag' == 1, `vceopt'
    local replay regress
    local ename 系数（概率差）
}
if "`model'" == "mpoisson" {
    local cmd poisson `y' `X' if `flag' == 1, irr `vceopt'
    local replay poisson, irr
    local ename RR
}
if "`model'" == "ols" {
    local cmd regress `y' `X' if `flag' == 1, `vceopt'
    local replay regress
    local ename 系数
}
if "`model'" == "ologit" {
    local cmd ologit `y' `X' if `flag' == 1, or `vceopt'
    local replay ologit, or
    local ename OR
}
if "`model'" == "oprobit" {
    local cmd oprobit `y' `X' if `flag' == 1, `vceopt'
    local replay oprobit
    local ename 系数
}
if "`model'" == "mlogit" {
    local cmd mlogit `y' `X' if `flag' == 1, rrr baseoutcome(`base') `vceopt'
    local replay mlogit, rrr
    local ename RRR
}
if inlist("`model'", "poisson", "nbreg") {
    local expo = cond("`exposure'" == "", "", "exposure(`exposure')")
    local cmd `model' `y' `X' if `flag' == 1, irr `expo' `vceopt'
    local replay `model', irr
    local ename IRR
}
if "`model'" == "cox" {
    local cmd stcox `X' if `flag' == 1, `vceopt'
    local replay stcox
    local ename HR
}

* 【4-2】估计模型
display _n as text "【多变量回归】`cmd'"
`cmd'
estimates store ubm_main


* ====== （五）结果汇总 ======
* 以下只复述（一）至（四）的结果，供写入结果文件，不是新的分析

display _n as text "==================== 结果汇总 ===================="
quietly count
local N0 = r(N)
quietly count if `flag' == 1
local N = r(N)
display as text "【样本】全部观测=`N0' | 分析样本=`N'（`flag' == 1）| 因变量类型=`ytype' | 模型=`model'"
if "`vceopt'" != "" {
    display as text "【样本】标准误：`vceopt'"
}

* 单变量：连续变量
foreach v of local ucont {
    quietly summarize `v' if `flag' == 1
    local n  = r(N)
    local m  = strtrim(string(r(mean), "%12.2f"))
    local sd = strtrim(string(r(sd), "%12.2f"))
    display as text "【单变量-连续】`v' | N=`n' | 均值=`m' | 标准差=`sd'"
}

* 单变量：分类变量
foreach v of local ucat {
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

* 双变量：二分类因变量的 t 检验
if "`ytype'" == "binary" {
    foreach v of local xcont {
        _ubm_tsum `v' `y' `flag'
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
            _ubm_tsum `y' `v' `flag'
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
        quietly levelsof `v' if `flag' == 1, local(levs)
        foreach l of local levs {
            quietly count if `v' == `l' & `flag' == 1
            local nl = r(N)
            local lab : label (`v') `l'
            local lab = cond("`lab'" == "`l'", "", "（`lab'）")
            local cells ""
            foreach c of local ylevs {
                quietly count if `v' == `l' & `y' == `c' & `flag' == 1
                local pc = strtrim(string(100 * r(N) / `nl', "%12.1f"))
                local cells "`cells' | `y'=`c'：`r(N)'（`pc'）"
            }
            display as text "【双变量-卡方-分组】`v'=`l'`lab' | 合计=`nl'`cells'"
        }
    }
}

* 双变量：有暴露量的计数因变量（粗 IRR）
if "`ytype'" == "count" & "`exposure'" != "" {
    foreach t in `xcont' `xcati' {
        quietly `model' `y' `t' if `flag' == 1, irr exposure(`exposure') `vceopt'
        quietly `model', irr
        tempname T
        matrix `T' = r(table)
        _ubm_effects "双变量-粗效应" "IRR" `T' 1
    }
}

* 双变量：生存因变量
if "`ytype'" == "survival" {
    foreach v of local xcont {
        quietly stcox `v' if `flag' == 1, `vceopt'
        quietly stcox
        tempname T
        matrix `T' = r(table)
        _ubm_effects "双变量-粗效应" "HR" `T' 1
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

* 多变量
estimates restore ubm_main
quietly `replay'
tempname T
matrix `T' = r(table)
_ubm_fit `N'
_ubm_effects "多变量-效应" "`ename'" `T'
display as text "==================== 汇总结束 ===================="
