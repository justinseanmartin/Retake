#!/usr/bin/env python3
"""Rewrites edit files for the anchor rule of 2026-11-06, keeping their layout.

Before, an anchor with no "edge" counted an offset or fraction of 0 or more from its step's end;
now every anchor counts from its step's start unless "edge" is "end". So each anchor with a "step",
an "offset" or "fraction" of 0 or more, and no "edge" gains "edge": "end" after its last field, and
lands where it did. Nothing else changes: a negative value with no edge, and any anchor that names
its edge, mean what they meant.

Usage: Scripts/migrate-anchors.py <project>/Retake/edits/*.json [--check]
With --check, lists what would change and writes nothing.
"""

import json
import re
import sys

NUMBER = re.compile(r"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?")
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')


class Scanner:
    """A JSON reader that keeps where each object's last value ends, to insert after it."""

    def __init__(self, text):
        self.text, self.at, self.insertions = text, 0, []

    def space(self):
        while self.at < len(self.text) and self.text[self.at] in " \t\r\n":
            self.at += 1

    def value(self):
        self.space()
        char = self.text[self.at]
        if char == "{":
            return self.object()
        if char == "[":
            self.at += 1
            items = []
            self.space()
            if self.text[self.at] == "]":
                self.at += 1
                return items
            while True:
                items.append(self.value())
                self.space()
                self.at += 1
                if self.text[self.at - 1] == "]":
                    return items
        if char == '"':
            match = STRING.match(self.text, self.at)
            self.at = match.end()
            return json.loads(match.group(0))
        for word, meaning in (("true", True), ("false", False), ("null", None)):
            if self.text.startswith(word, self.at):
                self.at += len(word)
                return meaning
        match = NUMBER.match(self.text, self.at)
        if not match:
            raise ValueError(f"not JSON at character {self.at}")
        self.at = match.end()
        return float(match.group(0))

    def object(self):
        self.at += 1
        fields, last_end = {}, None
        self.space()
        if self.text[self.at] == "}":
            self.at += 1
            return fields
        while True:
            self.space()
            key = self.value()
            self.space()
            self.at += 1  # the colon
            fields[key] = self.value()
            last_end = self.at
            self.space()
            self.at += 1
            if self.text[self.at - 1] == "}":
                break
        value = fields.get("offset", fields.get("fraction"))
        if "step" in fields and "edge" not in fields and isinstance(value, float) and value >= 0:
            self.insertions.append(last_end)
        return fields


def migrate(text):
    scanner = Scanner(text)
    scanner.value()
    for at in sorted(scanner.insertions, reverse=True):
        text = text[:at] + ', "edge": "end"' + text[at:]
    return text, len(scanner.insertions)


def main(arguments):
    check = "--check" in arguments
    paths = [argument for argument in arguments if argument != "--check"]
    if not paths:
        sys.exit(__doc__.strip())
    for path in paths:
        with open(path, encoding="utf-8") as file:
            text = file.read()
        migrated, count = migrate(text)
        print(f"{path}: {count} anchor{'' if count == 1 else 's'} given \"edge\": \"end\"")
        if count and not check:
            with open(path, "w", encoding="utf-8") as file:
                file.write(migrated)


if __name__ == "__main__":
    main(sys.argv[1:])
