# 回归测试

改动模板后，用这里的脚本把全部案例重跑一遍，确认结果没有意外变化。案例只用公开数据：Stata 自带数据，以及 Stata 手册的示例数据。

## 步骤

1. 生成测试数据（需联网下载手册示例数据）：

   ```bash
   mkdir -p tests/work && cd tests/work
   /Applications/Stata/StataSE.app/Contents/MacOS/stata-se -b do ../make_data.do
   cd ../..
   ```

2. 运行测试（在仓库根目录）：

   ```bash
   python3 tests/run_tests.py
   ```

   每个案例输出 PASS 或 FAIL。FAIL 的原因有两种：
   - 是否出错与预期不符；
   - “结果汇总”段与 `tests/expected/` 中的基准不同。

3. 有意改动了汇总格式或算法时，先逐项核对新结果，确认无误后再更新基准：

   ```bash
   python3 tests/run_tests.py --update
   ```

## 案例

`cases.txt` 每行一个案例：名称、预期结果（OK 或出错代码）、参数。名称前缀表示用途：

| 前缀 | 用途 |
| --- | --- |
| `x_` `k_` `b_` `t_` | 1.1.0 已有的 11 种模型与特殊情形（暴露量、聚类、完全预测、改参照组） |
| `n_` | 2.0.0 新增的模型：qreg、tobit、zinb、zip、weibull、crreg |
| `f_` | 逐步加入变量、不假定方差相等的 t 检验 |
| `s_` | 复杂抽样设计（NHANES II） |
| `m_` | 多重插补模块用的基础案例 |
| `e_` | 参数或数据有误时，应给出中文提示并按预期代码退出 |

各模型的关键数字都曾与直接执行的 Stata 命令逐项核对，核对过程未纳入本目录。

用 Stata 16 SE（macOS）生成基准。其他版本的 Stata 若在数值的末位有差异，以人工核对为准。
