# Stata 常见陷阱

写可选模块、帮用户整理变量或排错时对照本表。各条或来自 Stata 手册，或经 Stata 16 SE（macOS）实测；“缺失值最大”“`=` 与 `==`”“`capture` 吞错”“权数类型”等通用条目，参考了 dylantmoore/stata-skill 的 Critical Gotchas 一节。

## 写命令

| 现象 | 原因 | 做法 |
| --- | --- | --- |
| `generate old = (age >= 80)` 把年龄缺失的人也记为 1 | 数值缺失值 `.`（以及 `.a`—`.z`）大于任何数 | 写成 `generate old = (age >= 80) if !missing(age)`；条件判断一律考虑缺失 |
| 由各题项累加生成的变量偏小 | `inlist(., 2, 3)` 为假，缺失的题项按“未发生”计入 | 累加前用 `misstable summarize` 看题项缺失，或另设规则，由用户决定 |
| `if status = 1` 报语法错误 | `=` 是赋值，`==` 才是比较 | 条件里一律用 `==` |
| 分类变量被当作连续变量 | 回归中没写 `i.` | 分类变量写 `i.变量`，改参照组写 `ib#.变量` |
| 局部宏取不到值，或报 invalid name | 用了中文输入法的引号‘’，或少了右引号 | 宏一律写成 `` `name' ``：左边是键盘左上角的反引号，右边是英文单引号 |
| 命令报 invalid syntax，却看不出错 | 混进了中文全角标点（，（）：） | 命令、选项、括号一律用英文半角；中文只放在引号内的标签与标题里 |
| 参数行改完后报 r(198) | 值与行末的 `//` 之间没有空格 | 值与 `//` 之间至少留一个空格 |
| 变量名写一半也能运行，换数据后却出错 | 缺省允许变量名缩写 | 模板已 `set varabbrev off`，变量名须写全 |
| 出错后程序照常往下走，结果是错的 | `capture` 吞掉了错误 | 只在已知可能失败处用 `capture`，随后检查 `_rc`；分析命令不加 `capture` |
| 一行太长写不下 | 命令须写在一行 | 用 `///` 续行 |
| `tabulate` 的合计少于观测数 | 缺省不列缺失值 | 核对时加 `missing` 选项 |
| 字符串变量不能进回归，报 r(7) 或 r(109) | 变量是字符串型 | 数字存成文本的用 `destring`，类别文字用 `encode` 转为带值标签的数值变量 |
| 合并后样本量不对 | 键变量不唯一或类型不一致 | 合并前 `duplicates report 键变量`，合并后 `tabulate _merge` 再处理 |

## 权数与抽样设计

| 现象 | 原因 | 做法 |
| --- | --- | --- |
| 用了权数，标准误仍按简单随机抽样计算 | 只在命令里加了 `[pw=…]`，没有声明 PSU 与分层 | 用 `svyset psu [pweight = wt], strata(层)` 声明设计，估计加 `svy` 前缀 |
| 子总体分析的标准误不对 | 抽样调查数据用 `if` 限定子样本 | 用 `svy, subpop(标记变量):`，不用 `if`，也不删除观测 |
| 用 `fweight` 把抽样权数当频数权数 | 权数类型用错 | 抽样权数是 `pweight`；`aweight` 只用于加权的点估计；`fweight` 只用于频数数据 |
| `svy:` 命令里加 `vce(robust)` 报 r(198) | 抽样设计下标准误由 `svyset` 决定（实测） | 去掉 `vce()`，聚类变量写进 `svyset` 的 PSU |
| 某层只有一个 PSU，标准误为缺失 | 单 PSU 层 | 用 `svydescribe` 查看，按用户与数据文档决定 `singleunit()` 的处理方式 |
| `estat gof` 报 r(198) | 按子总体估计后不能使用（实测） | 抽样调查数据不做该检验 |
| `margins` 的平均边际效应用了分析样本以外的观测 | 按子总体估计后，`e(sample)` 仍含全部观测，`margins` 缺省在全部观测上平均（实测） | `margins` 加 `subpop(标记变量)` |
| 回归表的观测数比分析样本多 | 抽样设计下 `e(N)` 是全部观测数 | 子总体观测数取 `e(N_sub)`，导出时另列 |

## 运行与输出

| 现象 | 原因 | 做法 |
| --- | --- | --- |
| 命令行批处理出错，退出码却是 0 | Stata 16 SE（macOS）批处理出错时仍返回 0（实测） | 一律查日志中有无 `r(数字);` 行 |
| `graph export … .png` 报 r(111) 或 translator 错误 | 命令行（控制台）版 Stata 不能导出 PNG（实测） | 先导出 PDF，再 `capture` 导出 PNG |
| 图中中文显示为方框 | 所用字体不含中文 | macOS 的 Stata 16 导出 PDF 时中文正常（实测）；其他系统未实测，出现方框时请用户在 Stata 的图形字体设置中改用含中文的字体 |
| `outreg2` 无法写入结果文件 | 结果文件可能正在 Word 中打开 | 关闭 Word 后重跑，或换文件名 |
| `outreg2` 加 `eform` 后多出因变量空行 | `eform` 把方程名也列成一行（实测） | 加 `drop(因变量)`；Cox 与竞争风险模型加 `drop(_t)` |
| nbreg 用 `outreg2` 导出后多出一行 lnalpha，数值实为 alpha | `eform` 把 lnalpha 也取了指数（实测） | nbreg 改用 `esttab …, eform drop(/:)` |
| 有切点或多个方程的模型导出后表格错乱 | outreg2 不区分辅助方程 | 用 `esttab`：ologit、oprobit、tobit、nbreg、weibull 加 `drop(/:)`，zinb 加 `drop(inflate: /:)`，zip 加 `drop(inflate:)`，mlogit 加 `unstack drop(基准结局:)` |
| `ssc install` 失败 | 网络不通或 SSC 无法访问 | 稍后重试；或从作者的 GitHub 安装，如 `net install coefplot, from("https://raw.githubusercontent.com/benjann/coefplot/master/") replace`；装包须经用户同意 |
| 新装的命令包找不到 | 程序缓存未更新 | 运行 `discard`，再用 `which 命令名` 确认安装位置 |
| 连接器回传结果时报编码错误 | 项目路径含中文 | 把项目复制到全英文路径下再运行；do 文件与日志里写中文没有问题 |

## 版本

模板只用 Stata 16 已有的命令，在 Stata 16 SE（macOS）上实测。更高版本与 Windows、Linux 未实测；新版本中个别命令的语法有变化时，以所用版本的帮助文件为准（`help 命令名`）。
