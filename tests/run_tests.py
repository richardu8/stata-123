# 日期：2026-11-02
# 用途：回归测试——按 cases.txt 逐个填写模板参数区，用 Stata 批处理运行，
#       核对是否按预期出错，并把“结果汇总”段与 expected/ 中的基准逐行比较
# 输入：skills/stata-123/assets/analysis-template.do；tests/cases.txt；tests/work/inputs/*.dta（由 make_data.do 生成）
# 输出：tests/work/ 下的 do 文件与日志；屏幕上的 PASS/FAIL；--update 时改写 expected/*.txt
#
# 用法（在仓库根目录）：
#   python3 tests/run_tests.py                      # 跑全部案例
#   python3 tests/run_tests.py x_logit s_bin        # 只跑指定案例
#   python3 tests/run_tests.py --update             # 核对无误后，把当前结果存为新基准
#   STATA=/path/to/stata-se python3 tests/run_tests.py   # 指定 Stata 程序
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TPL = ROOT / "skills" / "stata-123" / "assets" / "analysis-template.do"
TESTS = ROOT / "tests"
WORK = TESTS / "work"
EXPECTED = TESTS / "expected"
STATA = os.environ.get("STATA", "/Applications/Stata/StataSE.app/Contents/MacOS/stata-se")


def fill(src, kv):
    """按 key=value 改写参数区，保留行末注释；值与注释之间至少留一个空格。"""
    lines, seen = src.split("\n"), set()
    for i, line in enumerate(lines):
        if line.startswith("* 日期：YYYY-MM-DD"):
            lines[i] = "* 日期：2026-11-02"
        m = re.match(r"^local (\w+)(\s+)(.*?)(\s*)(// .*)$", line)
        if m and m.group(1) in kv and m.group(1) not in seen:
            key, val, com = m.group(1), kv[m.group(1)], m.group(5)
            if key == "data":
                val = f'"{val}"'
            lines[i] = f"local {key.ljust(8)} {val}".ljust(39) + " " + com
            seen.add(key)
    missing = set(kv) - seen
    if missing:
        raise SystemExit(f"参数区没有这些参数：{missing}")
    return "\n".join(lines)


def summary(log):
    """取“结果汇总”段中以【开头的行。"""
    out, on = [], False
    for line in log.split("\n"):
        if "==== 结果汇总 ====" in line and not line.startswith("."):
            on = True
            continue
        if "==== 汇总结束 ====" in line and not line.startswith("."):
            break
        if on and line.startswith("【"):
            out.append(line.rstrip())
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    update = "--update" in sys.argv
    (WORK / "do").mkdir(parents=True, exist_ok=True)
    EXPECTED.mkdir(exist_ok=True)
    src = TPL.read_text(encoding="utf-8")
    n_pass = n_fail = 0
    for raw in (TESTS / "cases.txt").read_text(encoding="utf-8").split("\n"):
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        parts = [p.strip() for p in raw.split(" ;; ")]
        name, kv = parts[0], dict(p.split("=", 1) for p in parts[1:])
        if args and name not in args:
            continue
        expect = kv.pop("expect", "OK")
        (WORK / "do" / f"{name}.do").write_text(fill(src, kv), encoding="utf-8")
        subprocess.run([STATA, "-b", "do", f"do/{name}.do"], cwd=WORK, check=False)
        log = (WORK / f"{name}.log").read_text(encoding="utf-8", errors="replace")
        codes = re.findall(r"^r\((\d+)\);", log, flags=re.M)
        got = codes[0] if codes else "OK"
        problems = []
        if got != expect:
            problems.append(f"预期 {expect}，实际 {got}")
        if expect == "OK" and got == "OK":
            cur = summary(log)
            ref = EXPECTED / f"{name}.txt"
            if update:
                ref.write_text("\n".join(cur) + "\n", encoding="utf-8")
            elif ref.exists():
                old = ref.read_text(encoding="utf-8").rstrip("\n").split("\n")
                if old != cur:
                    diff = [l for l in old if l not in cur][:3]
                    problems.append("汇总与基准不同，例如：" + " / ".join(diff))
            else:
                problems.append("没有基准，核对后用 --update 生成")
        if problems:
            n_fail += 1
            print(f"FAIL {name}：" + "；".join(problems))
        else:
            n_pass += 1
            print(f"PASS {name}")
    print(f"\n通过 {n_pass}，未通过 {n_fail}")
    sys.exit(1 if n_fail else 0)


if __name__ == "__main__":
    main()
