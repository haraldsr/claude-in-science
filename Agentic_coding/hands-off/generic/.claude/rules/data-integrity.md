# Data integrity

<!-- Hard constraints for pipelines that read values, detect things, or score outputs against
a reference. Loaded every session with the same standing as CLAUDE.md. Delete this file in a
project where none of it applies. -->

Hard constraints — same standing as the ones in `CLAUDE.md`: if one blocks you, stop and ask.

- Never fabricate a value from an indirect signal. If a value must be *read* from a source,
  read it. Never infer it from a correlated proxy — a colour, a position, a naming convention,
  or what you'd expect to see there. A plausible-looking wrong number is the worst possible
  output.
- Never hardcode domain values. No magic domain constants, expected names or expected ranges
  baked into code. Everything comes from the input or from an autonomous detector — never
  from what a known test case happens to contain.
- Never hardcode counts, lower OR upper. No `len(...) > 12`, `n / 8.0`,
  `if count > 14: penalize`. Acceptable: a structural floor (e.g. `>= 2` where one element
  is meaningless) or a generous safety ceiling — clearly commented as such, and never
  matching any case we test against.
- Evaluation data never feeds what it grades. Ground truth, expected outputs and reference
  answers flow one way, into scoring only. If a value can reach the code path it grades, the
  score is meaningless.
- Human corrections: sidecar files only, single run only. Corrections enter through an
  explicit sidecar, never CLI flags; they stamp the run as assisted so headline scores can
  exclude it; they never mix with evaluation data in either direction; and they are never
  reused by a later run. Reuse is cheating.
- Staged debug artifacts are mandatory. Any non-trivial detector or heuristic change emits
  an artifact for EACH decision step — candidates, filters, accept/reject reason. A
  final-only overlay is not enough to diagnose a failure.
