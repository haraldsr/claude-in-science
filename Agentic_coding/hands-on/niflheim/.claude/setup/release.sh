#!/usr/bin/env bash
# Release the setup gate: delete the marker, the two setup hooks, the setup skill and this
# directory, and unwire the hooks from settings.json.
#
# This is a script rather than "ask Claude to edit settings.json" on purpose: unwiring means
# surgery on the file that wires every other guard, and a mangled settings.json silently
# disarms all of them. Here it is a parsed edit with assertions, and the result is validated
# before anything is deleted.
#
# Run it from /setup's last step, or by hand to abandon setup. It deletes itself last, so
# there is nothing to re-run; if it is already gone, setup was already released.
set -eu
proj="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$proj"
S=".claude/settings.json"
[ -f "$S" ] || { echo "release: no $S in $proj — wrong directory?" >&2; exit 1; }

python3 - "$S" <<'PY'
import json, sys, copy
p = sys.argv[1]
with open(p) as f:
    before = f.read()
j = json.loads(before)                       # a broken file fails here, before any deletion
after = copy.deepcopy(j)
names = ("setup_gate.sh", "block_until_setup.sh")
removed = []
for event, groups in list(after.get("hooks", {}).items()):
    for g in groups:
        keep = []
        for h in g.get("hooks", []):
            if any(n in h.get("command", "") for n in names):
                removed.append(f"{event}:{h['command'].rsplit('/',1)[-1]}")
            else:
                keep.append(h)
        g["hooks"] = keep
    groups[:] = [g for g in groups if g.get("hooks")]
after["hooks"] = {e: gs for e, gs in after["hooks"].items() if gs}

# Every other hook must survive untouched: this edit removes exactly the setup pair.
def wired(d):
    return sorted(h["command"] for gs in d.get("hooks", {}).values() for g in gs for h in g["hooks"])
lost = [c for c in wired(j) if c not in wired(after) and not any(n in c for n in names)]
assert not lost, f"release would have removed unrelated hooks: {lost}"

with open(p, "w") as f:
    json.dump(after, f, indent=2)
    f.write("\n")
json.load(open(p))                           # re-parse what we just wrote
print("unwired: " + (", ".join(removed) if removed else "nothing (already released)"))
PY

# Strip the gate section from CLAUDE.md, between its two marker comments.
python3 - CLAUDE.md <<'GATEPY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
if p.exists():
    s = p.read_text()
    new, n = re.subn(r"<!-- SETUP-GATE-START.*?SETUP-GATE-END -->\n+", "", s, flags=re.S)
    assert n <= 1, "more than one gate section in CLAUDE.md - refusing to guess"
    if n:
        assert "Hard constraints" in new, "stripping the gate would have removed the rules too"
        p.write_text(new)
        print("CLAUDE.md: gate section removed")
    else:
        print("CLAUDE.md: no gate section (already released)")
GATEPY

rm -f .claude/hooks/setup_gate.sh .claude/hooks/block_until_setup.sh
rm -rf .claude/skills/setup
rm -f .claude/setup/SETUP_REQUIRED .claude/setup/SETUP_IN_PROGRESS \
      .claude/setup/SETUP_IN_PROGRESS.template .claude/setup/project.md.template \
      .claude/setup/dir-CLAUDE.md.template \
      .claude/setup/CHECKLIST.md \
      .claude/setup/.blocked_word
rm -f "$0" 2>/dev/null || true
rmdir .claude/setup 2>/dev/null || true

echo "released: setup marker, gate hooks and /setup removed."
if [ -f .claude/hooks/test_hooks.sh ]; then   # -f, not -x: a copy may have dropped the bit
  echo "verifying the remaining guards still pass..."
  bash .claude/hooks/test_hooks.sh | tail -1
fi
