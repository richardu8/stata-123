# 可选模块

只在用户明确要求时使用。代码接在 do 文件第（五）段之后，作为“（六）可选模块”，沿用参数区的 `y`、`xcont`、`flag` 与第（一）段生成的 `xcati`；每条分析命令同样带 `if analysis == 1`（或所设的标记名）。

这些模块要用外部命令包 outreg2、coefplot。Stata 连接器在默认权限下装包须由用户确认；装包被拦截或断网时，请用户在 Stata 命令窗口自行运行 `ssc install outreg2`、`ssc install coefplot`，不要绕过拦截。

```stata
* ====== （六）可选模块 ======
capture mkdir "outputs"      // 存放导出的表与图；已存在则跳过
```

## A. 导出 OR 表（Word）

```stata
* 【6-1】把主模型的 OR 导出为 Word 表：eform 报告 OR，dec(2) 保留两位小数；
*        drop() 去掉 eform 时多出的一行空的因变量
capture which outreg2
if _rc ssc install outreg2
estimates restore ubm_logit
outreg2 using "outputs/logit_or.doc", replace eform dec(2) label drop(`y') ctitle(`y') title("Logit results")
```

## B. OR 图

```stata
* 【6-2】画 OR 及其 95% 置信区间，竖虚线为 OR = 1
capture which coefplot
if _rc ssc install coefplot
estimates restore ubm_logit
coefplot, eform drop(_cons) xline(1, lpattern(dash)) xtitle("OR及95%置信区间")
graph export "outputs/logit_or.pdf", replace
* 命令行（控制台）版 Stata 不能导出 PNG，报错 r(111) 时保留上面的 PDF 即可
capture graph export "outputs/logit_or.png", replace width(2000)
if _rc display as text "本次运行的 Stata 不能导出 PNG，已导出 PDF：outputs/logit_or.pdf"
```

## C. 稳健性检验

每一项所需的信息都由用户给出，不自行设定。各项的结果用 `outreg2 … append` 并入 A 的同一张表。写结果时另列表6，逐项说明与主模型相比，各 OR 的方向与显著性是否改变。新变量在分析样本内有缺失时，写明实际使用的样本量。

1. **换因变量口径**：用户给出新口径的构造规则，如“六项日常活动中至少两项需要帮助才算失能”。

```stata
* 【6-3】新口径的因变量：数出每人需要帮助的项数，至少两项记 1
generate byte adl_n = 0
foreach v of varlist e1 e2 e3 e4 e5 e6 {
    replace adl_n = adl_n + 1 if inlist(`v', 2, 3)
}
generate byte disabled2 = (adl_n >= 2)
logit disabled2 `xcont' `xcati' if `flag' == 1, or
outreg2 using "outputs/logit_or.doc", append eform dec(2) label drop(disabled2) ctitle(disabled2)
```

2. **换标准误**：稳健标准误用 `vce(robust)`；聚类标准误用 `vce(cluster 变量)`，聚类变量由用户给出，如省份。

```stata
* 【6-4】稳健标准误与按省份聚类的标准误
logit `y' `xcont' `xcati' if `flag' == 1, or vce(robust)
outreg2 using "outputs/logit_or.doc", append eform dec(2) label drop(`y') ctitle(vce(robust))
logit `y' `xcont' `xcati' if `flag' == 1, or vce(cluster prov)
outreg2 using "outputs/logit_or.doc", append eform dec(2) label drop(`y') ctitle(vce(cluster prov))
```

3. **连续自变量改为分组**：用户给出切点与组名。改组后的变量以 `i.` 进入，原连续变量从模型中去掉。

```stata
* 【6-5】受教育年限分四组：0 未上过学；1–6 小学；7–9 初中；10 及以上 高中及以上
recode edu (0 = 1) (1/6 = 2) (7/9 = 3) (10/max = 4), generate(edu4)
label define edu4lb 1 "未上过学" 2 "小学" 3 "初中" 4 "高中及以上", replace
label values edu4 edu4lb
tabulate edu edu4 if `flag' == 1, missing
local old edu                            // 被替换的连续变量
local xcont_noedu : list xcont - old     // list 运算的两边都须是宏名
logit `y' `xcont_noedu' i.edu4 `xcati' if `flag' == 1, or
outreg2 using "outputs/logit_or.doc", append eform dec(2) label drop(`y') ctitle(edu4)
```

以上代码中的 `e1`—`e6`、`prov`、`edu` 与切点都是示例，按用户给出的变量和规则替换。
