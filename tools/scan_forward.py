"""Report any file-level local (function or variable) that is referenced in
code above the line where it is declared. In Lua such a reference resolves
to a global, which is nil. Forward declarations of the form
`local NAME -- comment` are honoured."""
import io, re, sys

path = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\noftz\Dev\better_group_tracking\QuestObjectivesPlus\QuestObjectivesPlus.lua"
s = io.open(path, encoding="utf-8").read()
lines = s.split("\n")

STRING_DQ = re.compile(r'"(?:\\.|[^"\\])*"')
STRING_SQ = re.compile(r"'(?:\\.|[^'\\])*'")

def code_only(line):
    line = STRING_DQ.sub('""', line)
    line = STRING_SQ.sub("''", line)
    return line.split("--")[0]

defs = {}
for i, line in enumerate(lines):
    m = re.match(r"local function (\w+)\b", line) or re.match(r"local (\w+)\s*=", line)
    if m and m.group(1) not in defs:
        defs[m.group(1)] = i
forward = set(re.findall(r"^local (\w+)\s*--", s, re.M))

bad = []
for name, at in defs.items():
    if name in forward:
        continue
    rx = re.compile(r"(?<![\w.])" + re.escape(name) + r"(?!\w)")
    for i in range(at):
        if rx.search(code_only(lines[i])):
            bad.append((name, at + 1, i + 1, lines[i].strip()[:70]))
            break

if bad:
    for name, at, use, text in bad:
        print(f"USED BEFORE DEFINITION: {name} (declared line {at}) used line {use}: {text}")
    sys.exit(1)
print("no local used before its definition")
