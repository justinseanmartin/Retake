#!/usr/bin/env python3
"""Reports how long each test took, from Swift Testing's event stream:

    swift test --experimental-event-stream-output events.jsonl --experimental-event-stream-version 0
    Scripts/test-timings.py events.jsonl

swift test writes that file when it finishes. While it runs, each test product's stream is written
as each event happens, to $TMPDIR/swiftpm-test-output-*/event-stream-*.jsonl, which stays when a
run hangs and is killed; given those, it lists first the tests that started and never ended. Then
come the slowest tests and suites. With GITHUB_STEP_SUMMARY set, as in GitHub Actions, it also
adds the report to the run's summary.

Usage: test-timings.py [--top <how many of the slowest to list, 15 by default>] <stream.jsonl>...
"""

import json
import os
import sys


def read(paths):
    """Each test's kind and name, when it started, and when it ended if it did."""
    kinds, names, started, ended = {}, {}, {}, {}
    for path in paths:
        with open(path, encoding="utf-8") as stream:
            lines = list(stream)
        for line in lines:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue  # A line cut short when the run was killed.
            payload = record.get("payload", {})
            if record.get("kind") == "test":
                kinds[payload["id"]] = payload.get("kind")
                names[payload["id"]] = payload.get("name")
            elif record.get("kind") == "event" and "testID" in payload:
                when = payload["instant"]["absolute"]
                if payload["kind"] == "testStarted":
                    started[payload["testID"]] = when
                elif payload["kind"] == "testEnded":
                    ended[payload["testID"]] = when
    return kinds, names, started, ended


def label(test_id, names):
    """`Module.Suite/test()` as `Suite/test()`, without the source location the ID ends with."""
    parts = test_id.split("/")
    if len(parts) > 1 and ".swift:" in parts[-1]:
        parts = parts[:-1]
    parts[0] = parts[0].split(".", 1)[-1]
    return "/".join(parts) if len(parts) > 1 else names.get(test_id) or parts[0]


def report(paths, count):
    kinds, names, started, ended = read(paths)
    unfinished = sorted((test for test in started if test not in ended and kinds.get(test) != "suite"), key=started.get)
    durations = {test: ended[test] - started[test] for test in started if test in ended}
    functions = sorted((test for test in durations if kinds.get(test) != "suite"), key=durations.get, reverse=True)
    suites = sorted((test for test in durations if kinds.get(test) == "suite"), key=durations.get, reverse=True)

    lines = ["## Test timings", ""]
    if not started:
        lines.append(f"No test started, going by {', '.join(os.path.basename(path) for path in paths)}.")
        return lines
    if unfinished:
        last = max(max(started.values()), max(ended.values(), default=0))
        lines += [f"**{len(unfinished)} tests started and never ended**, the run's last event being:", ""]
        lines += [f"- `{label(test, names)}`, started {last - started[test]:.1f} s before it" for test in unfinished]
        lines.append("")
    lines += [f"{len(functions)} tests ended, taking {sum(durations[t] for t in functions):.1f} s between them.", ""]
    for title, tests in (("Slowest tests", functions), ("Slowest suites", suites)):
        if tests:
            lines += [f"### {title}", "", "| Time | Test |", "| ---: | --- |"]
            lines += [f"| {durations[test]:.3f} s | `{label(test, names)}` |" for test in tests[:count]]
            lines.append("")
    return lines


def main():
    arguments = sys.argv[1:]
    count = 15
    if arguments[:1] == ["--top"] and len(arguments) > 1:
        count, arguments = int(arguments[1]), arguments[2:]
    if not arguments:
        sys.exit(__doc__.strip().splitlines()[-1])
    if missing := [path for path in arguments if not os.path.exists(path)]:
        sys.exit(f"error: no event stream at {', '.join(missing)}; did swift test start?")
    lines = report(arguments, count)
    text = "\n".join(lines) + "\n"
    print(text)
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a", encoding="utf-8") as out:
            out.write(text)


if __name__ == "__main__":
    main()
