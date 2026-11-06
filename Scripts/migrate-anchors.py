#!/usr/bin/env python3
"""Rewrites edit files for the anchor rule of 2026-11-06, keeping their layout.

Before, an anchor with no "edge" counted an offset or fraction of 0 or more from its step's end,
and a negative one back from its start; an anchor that named its edge counted from that edge. Now
every anchor counts from its step's start unless "edge" is "end". So each anchor ends up with only
the edge it needs to land where it did: one with an "offset" or "fraction" of 0 or more and no
edge gains "edge": "end" after its last field, on a line of its own where that field is on one,
"edge": "start" is dropped with its comma, and the rest is left. An anchor at the take's "start"
or "end" step needs no edge, both being one moment.

A device type's override that lays an anchor's fields over the base's ("ipad": { "to": { "offset":
0.4 } }) is judged as the anchor it makes, the edge it inherits and the sign it gives together:
it gains the edge that keeps that anchor where it was when the inherited one would move it, which
can be "edge": "start" over a base that now says "end", and drops one it no longer needs.

Usage: Scripts/migrate-anchors.py <project>/Retake/edits/*.json [--check]
With --check, lists what would change and writes nothing. With --self-check, runs its own cases.
"""

import json
import re
import sys

NUMBER = re.compile(r"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?")
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
DEVICE_TYPES = ("iphone", "ipad")


class Node:
    """An object as written: each field's key, value, and where the field starts and ends."""

    def __init__(self, path):
        self.path, self.fields, self.open, self.close = path, [], None, None  # fields: (key, value, start, end)

    def get(self, key, default=None):
        return next((value for name, value, _, _ in self.fields if name == key), default)

    def has(self, key):
        return any(name == key for name, _, _, _ in self.fields)


class Scanner:
    """A JSON reader that keeps each object's fields and where they're written."""

    def __init__(self, text):
        self.text, self.at = text, 0

    def space(self):
        while self.at < len(self.text) and self.text[self.at] in " \t\r\n":
            self.at += 1

    def value(self, path=""):
        self.space()
        char = self.text[self.at]
        if char == "{":
            return self.object(path)
        if char == "[":
            self.at += 1
            items = []
            self.space()
            if self.text[self.at] == "]":
                self.at += 1
                return items
            while True:
                items.append(self.value(f"{path}[{len(items)}]"))
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

    def object(self, path):
        node = Node(path or "root")
        node.open = self.at
        self.at += 1
        self.space()
        if self.text[self.at] == "}":
            node.close = self.at
            self.at += 1
            return node
        while True:
            self.space()
            start = self.at
            key = self.value()
            self.space()
            self.at += 1  # the colon
            value = self.value(f"{path}.{key}" if path else key)
            node.fields.append((key, value, start, self.at))
            self.space()
            self.at += 1
            if self.text[self.at - 1] == "}":
                node.close = self.at - 1
                return node


class Merged:
    """An object as one device type reads it: its fields after overrides, and the objects written
    in the file that gave them, the first one and then each override laid over it, in order."""

    def __init__(self, node):
        self.fields, self.sources = {}, [node]


def merge(node, device):
    """`node` merged for `device` as Retake merges an edit: each object it holds merged, then its
    own override for `device` laid over it, objects key by key and lists and plain values replaced."""
    merged = Merged(node)
    for key, value, _, _ in node.fields:
        if key not in DEVICE_TYPES:
            merged.fields[key] = merge_value(value, device)
    override = node.get(device)
    if isinstance(override, Node):
        lay(override, merged, device)
    return merged


def lay(override, merged, device):
    merged.sources.append(override)
    for key, value, _, _ in override.fields:
        if key in DEVICE_TYPES:
            continue
        if isinstance(value, Node) and isinstance(merged.fields.get(key), Merged):
            lay(value, merged.fields[key], device)
        else:
            merged.fields[key] = merge_value(value, device)


def merge_value(value, device):
    if isinstance(value, Node):
        return merge(value, device)
    if isinstance(value, list):
        return [merge_value(item, device) for item in value]
    return value


def anchors(value):
    """Each merged anchor in `value`: each object with a step."""
    if isinstance(value, Merged):
        if "step" in value.fields:
            yield value
        for field in value.fields.values():
            yield from anchors(field)
    elif isinstance(value, list):
        for item in value:
            yield from anchors(item)


def nodes(value):
    if isinstance(value, Node):
        yield value
        for _, field, _, _ in value.fields:
            yield from nodes(field)
    elif isinstance(value, list):
        for item in value:
            yield from nodes(item)


def old_edge(fields):
    """The edge an anchor with `fields` counted from before 2026-11-06."""
    if "edge" in fields:
        return fields["edge"]
    value = fields.get("offset", fields.get("fraction"))
    return "end" if isinstance(value, float) and value >= 0 else "start"


def plan(root):
    """The edge each object written in the file should give, by its id: "start", "end", or None
    for none; and the ids of the overrides laid over another object. An anchor written whole needs
    "end" where it counted from its end; an override's fields need the edge that keeps the anchor
    they make where it was, when the one they inherit from what's under them wouldn't."""
    edges = {}
    under = {}  # an override's id: the objects under it, the anchor's first written object first
    devices = root.get("devices") if isinstance(root, Node) else None
    devices = [d for d in devices if d in DEVICE_TYPES] if isinstance(devices, list) else DEVICE_TYPES
    for device in devices:
        for anchor in anchors(merge_value(root, device)):
            for index, source in enumerate(anchor.sources[1:], 1):
                under[id(source)] = anchor.sources[:index]
    for node in nodes(root):
        if id(node) not in under and node.has("step"):
            edges[id(node)] = needed(scalars(node), "start", node.get("edge"))
    overrides = sorted((node for node in nodes(root) if id(node) in under), key=lambda node: len(under[id(node)]))
    for node in overrides:
        fields, inherited = {}, "start"
        for source in under[id(node)]:
            fields.update(scalars(source))
            inherited = (edges[id(source)] if id(source) in edges else source.get("edge")) or inherited
        fields.update(scalars(node))
        edges[id(node)] = needed(fields, inherited, node.get("edge"))
    return edges, set(under)


def needed(fields, inherited, given):
    """The edge an object should give, for the anchor it makes with `fields` to land where it did,
    when it inherits `inherited` from what's under it and now gives `given`. The take's start and
    end are a moment each, so an anchor at one needs no edge, though one given as "end" is kept."""
    wanted = old_edge(fields)
    if fields.get("step") in ("start", "end") and given != "end":
        return None
    return None if wanted == inherited else wanted


def scalars(node):
    return {key: value for key, value, _, _ in node.fields if not isinstance(value, (Node, list))}


def migrate(text):
    """`text` migrated, and what changed: for each object whose edge changed, how, where, and
    whether it's an override laid over another."""
    root = Scanner(text).value()
    edges, overrides = plan(root)
    changes = []  # (start, end, replacement)
    lines = []
    for node in nodes(root):
        if id(node) not in edges:
            continue
        wanted, given = edges[id(node)], node.get("edge")
        if wanted == given:
            continue
        index = next((i for i, field in enumerate(node.fields) if field[0] == "edge"), None)
        if wanted is None:
            if index > 0:
                start, end = node.fields[index - 1][3], node.fields[index][3]
            elif index + 1 < len(node.fields):
                start, end = node.fields[index][2], node.fields[index + 1][2]
            else:
                start, end = node.fields[index][2], node.fields[index][3]
            changes.append((start, end, ""))
            lines.append((f'drops "edge": "{given}"', node.path, id(node) in overrides))
        elif index is not None:
            _, _, start, end = node.fields[index]
            changes.append((start, end, f'"edge": "{wanted}"'))
            lines.append((f'gives "edge": "{wanted}" for "{given}"', node.path, id(node) in overrides))
        elif node.fields:
            # On a line of its own after the last field, where that field is on one of its own.
            before = node.fields[-2][3] if len(node.fields) > 1 else node.open + 1
            gap = text[before:node.fields[-1][2]]
            separator = ",\n" + gap.rsplit("\n", 1)[1] if "\n" in gap else ", "
            changes.append((node.fields[-1][3], node.fields[-1][3], f'{separator}"edge": "{wanted}"'))
            lines.append((f'gains "edge": "{wanted}"', node.path, id(node) in overrides))
        else:
            changes.append((node.close, node.close, f'"edge": "{wanted}"'))
            lines.append((f'gains "edge": "{wanted}"', node.path, id(node) in overrides))
    for start, end, replacement in sorted(changes, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text, lines


CASES = [
    # A positive offset with no edge counted from the end; a negative one, or none, from the start.
    ('{"a": {"step": 1, "offset": 0.2}, "b": {"step": 1, "offset": -0.2}, "c": {"step": 1}}',
     '{"a": {"step": 1, "offset": 0.2, "edge": "end"}, "b": {"step": 1, "offset": -0.2}, "c": {"step": 1}}'),
    ('{\n  "a": {\n    "step": 1,\n    "offset": 0.2\n  }\n}', '{\n  "a": {\n    "step": 1,\n    "offset": 0.2,\n    "edge": "end"\n  }\n}'),
    # "start" is the default now, wherever it's written in the object; "end" stays.
    ('{"a": {"step": 1, "offset": 0.2, "edge": "start"}, "b": {"edge": "start", "step": 2, "fraction": 0.5},'
     ' "c": {"step": 3, "offset": -1, "edge": "end"}}',
     '{"a": {"step": 1, "offset": 0.2}, "b": {"step": 2, "fraction": 0.5}, "c": {"step": 3, "offset": -1, "edge": "end"}}'),
    ('{\n  "a": {\n    "step": 1,\n    "edge": "start",\n    "offset": 0.2\n  }\n}',
     '{\n  "a": {\n    "step": 1,\n    "offset": 0.2\n  }\n}'),
    # An override's offset decides with the edge it inherits: here "end" over a base still at the
    # start, "start" over a base now at the end, and nothing where the inherited edge is right.
    ('{"to": {"step": 1, "offset": -0.2}, "ipad": {"to": {"offset": 0.4}}}',
     '{"to": {"step": 1, "offset": -0.2}, "ipad": {"to": {"offset": 0.4, "edge": "end"}}}'),
    ('{"to": {"step": 1, "offset": 0.2}, "ipad": {"to": {"offset": -0.4}}}',
     '{"to": {"step": 1, "offset": 0.2, "edge": "end"}, "ipad": {"to": {"offset": -0.4, "edge": "start"}}}'),
    ('{"to": {"step": 1, "offset": 0.2}, "ipad": {"to": {"offset": 0.4}}}',
     '{"to": {"step": 1, "offset": 0.2, "edge": "end"}, "ipad": {"to": {"offset": 0.4}}}'),
    ('{"to": {"step": 1, "offset": 0.2, "edge": "end"}, "ipad": {"to": {"edge": "start"}}}',
     '{"to": {"step": 1, "offset": 0.2, "edge": "end"}, "ipad": {"to": {"edge": "start"}}}'),
    ('{"to": {"step": 1, "offset": 0.2, "edge": "start"}, "ipad": {"to": {"step": 2, "edge": "start"}}}',
     '{"to": {"step": 1, "offset": 0.2}, "ipad": {"to": {"step": 2}}}'),
    # An override that replaces a list gives whole anchors, judged alone.
    ('{"clips": [{"to": {"step": 1, "offset": 0.2}}], "ipad": {"clips": [{"to": {"step": 1, "offset": 0.3, "edge": "start"}}]}}',
     '{"clips": [{"to": {"step": 1, "offset": 0.2, "edge": "end"}}], "ipad": {"clips": [{"to": {"step": 1, "offset": 0.3}}]}}'),
    # The take's start and end need no edge, and keep an "end" they give.
    ('{"a": {"step": "start", "offset": 5}, "b": {"step": "end", "offset": -1, "edge": "start"}, "c": {"step": "end", "edge": "end"}}',
     '{"a": {"step": "start", "offset": 5}, "b": {"step": "end", "offset": -1}, "c": {"step": "end", "edge": "end"}}'),
    # A step without an offset, as a touch colour names one, is left alone.
    ('{"touchColors": [{"step": 2, "color": "#FFFFFF"}]}', '{"touchColors": [{"step": 2, "color": "#FFFFFF"}]}'),
]


def new_edge(fields):
    """The edge an anchor with `fields` counts from since 2026-11-06."""
    return fields.get("edge", "start")


def meanings(text, edge):
    """Each device type's anchors in `text`, with the edge `edge` says each counts from, but for
    the take's start and end, where the edge is the same moment."""
    def meaning(merged):
        fields = {key: value for key, value in merged.fields.items() if not isinstance(value, (Merged, list))}
        at = None if fields["step"] in ("start", "end") else edge(fields)
        return at, {key: value for key, value in fields.items() if key != "edge"}

    root = Scanner(text).value()
    return [[meaning(merged) for merged in anchors(merge_value(root, device))] for device in DEVICE_TYPES]


def self_check():
    for before, after in CASES:
        migrated, _ = migrate(before)
        assert migrated == after, f"{before}\n  became {migrated}\n  not    {after}"
        assert meanings(before, old_edge) == meanings(migrated, new_edge), f"{before} moves an anchor"
    print(f"{len(CASES)} cases pass")


def main(arguments):
    if "--self-check" in arguments:
        return self_check()
    check = "--check" in arguments
    paths = [argument for argument in arguments if argument != "--check"]
    if not paths:
        sys.exit(__doc__.strip())
    for path in paths:
        with open(path, encoding="utf-8") as file:
            text = file.read()
        migrated, lines = migrate(text)
        if meanings(text, old_edge) != meanings(migrated, new_edge):
            sys.exit(f"{path}: migrating would move an anchor; edit it by hand")
        counts = {}
        for change, _, _ in lines:
            counts[change] = counts.get(change, 0) + 1
        summary = ", ".join(f"{count} {change}" for change, count in sorted(counts.items())) or "nothing to change"
        print(f"{path}: {summary}")
        for change, where, override in lines:
            if override:
                print(f"  {where}, an override, {change}")
        if lines and not check:
            with open(path, "w", encoding="utf-8") as file:
                file.write(migrated)


if __name__ == "__main__":
    main(sys.argv[1:])
