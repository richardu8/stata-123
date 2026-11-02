* =============================================================
* 日期：2026-11-02
* 用途：生成测试数据（Stata 自带数据与 Stata Press 网站上的手册示例数据）
* 输入：sysuse 自带数据；webuse 下载的 nhanes2f、fish、hypoxia（需联网）
* 输出：tests/work/inputs/ 下的 .dta 文件
* =============================================================
* 在 tests/work 目录运行：stata-se -b do ../make_data.do
clear all
set more off
capture mkdir "inputs"

* nlsw88：另建三类的有序变量 gradecat（受教育程度）
sysuse nlsw88, clear
generate byte gradecat = 1 + (grade >= 12) + (grade >= 16) if !missing(grade)
label define gclb 1 "高中以下" 2 "高中" 3 "大学"
label values gradecat gclb
save "inputs/nlsw88.dta", replace

sysuse census, clear
save "inputs/census.dta", replace
sysuse cancer, clear
save "inputs/cancer.dta", replace
sysuse auto, clear
save "inputs/auto.dta", replace

* 手册示例数据：复杂抽样设计、零膨胀计数、竞争风险
webuse nhanes2f, clear
save "inputs/nhanes2f.dta", replace
webuse fish, clear
save "inputs/fish.dta", replace
webuse hypoxia, clear
save "inputs/hypoxia.dta", replace
