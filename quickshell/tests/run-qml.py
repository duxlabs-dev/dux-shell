import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

repo = Path(__file__).resolve().parents[2]


def qml_test_runner():
    override = os.environ.get("QMLTESTRUNNER")
    candidates = [override] if override else ["qmltestrunner6", "/usr/lib/qt6/bin/qmltestrunner", "/usr/lib64/qt6/bin/qmltestrunner", "qmltestrunner"]
    for candidate in candidates:
        executable = shutil.which(candidate)
        if executable:
            return executable
    raise SystemExit("Qt 6 qmltestrunner is required; set QMLTESTRUNNER to its path")


def run(name, command):
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=repo, env=dict(os.environ, QT_QPA_PLATFORM="offscreen"), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    except OSError as error:
        return name, False, time.monotonic() - started, str(error)
    return name, result.returncode == 0, time.monotonic() - started, result.stdout


def main():
    parser = argparse.ArgumentParser(description="Run shell logic and Qt unit tests")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("suites", nargs="*", choices=["qt", "lock", "logic"])
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    selected = args.suites or ["qt", "lock", "logic"]
    commands = {
        "logic": ["node", "--test", *sorted(str(path.relative_to(repo)) for path in (repo / "quickshell/tests").glob("*.test.mjs"))],
    }
    if {"qt", "lock"} & set(selected):
        runner = qml_test_runner()
        commands["qt"] = [runner, "-input", "quickshell/tests/unit", "-o", "-,txt"]
        commands["lock"] = [runner, "-import", "quickshell/tests/lock/mocks", "-input", "quickshell/tests/lock", "-o", "-,txt"]
    started = time.monotonic()
    failed = False
    with ThreadPoolExecutor(max_workers=min(args.jobs, len(selected))) as pool:
        futures = [pool.submit(run, name, commands[name]) for name in selected]
        for future in as_completed(futures):
            name, passed, elapsed, output = future.result()
            print(f"{'PASS' if passed else 'FAIL'} {name}: {elapsed:.2f}s", flush=True)
            if not passed:
                failed = True
                print(output, flush=True)
                continue
            for line in output.splitlines():
                if any(token in line for token in ["Totals:", "# tests "]):
                    print(line.strip(), flush=True)
    print(f"QML checks: {time.monotonic() - started:.2f}s", flush=True)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
