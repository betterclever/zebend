# comp.ts sheds 485 tokens with the same output: shared lookups and flatter emitters

## Problem

`bend2/comp.ts` is at 65,994 of its permanent 66,000-token cap (tiktoken,
gpt-3.5-turbo), so any compiler change has to pay for itself first. This PR
makes room without changing what the compiler emits.

## What changed

All changes are in `bend2/comp.ts`, in the TypeScript compiler and emitters.
The C and JS runtime templates are unchanged.

- **Shared lookups:**
  - `FL.tlds` and `FL.ctrs` alias the book's tables (37 call sites).
  - `ty_key(t)` replaces five copies of `Bend.term_key(Bend.term_lower(t))`.
  - `let_vals(t, xs)` filters a let's live bindings for `term_kids` and `anf`.
- **Ternary chains** replace switches and if/return ladders in `term_kids`,
  `term_spine`, `call_eta`, `def_raise`, `term_uses` (now a reduce), `ty_srcs`,
  `mat_lits`'s `same`, `emit_expr`, `emit_body` (now with no switch),
  `emit_ctr`'s word builders and `js_match`.
- **compile_book:**
  - The `#define` block is one template laid out like the C it emits,
    replacing a `defs.push` of about 15 string pieces.
  - The fixpoint is a `for` loop.
  - The resets, the foreign/body emit and the live filters each take one
    statement.
- **Small cleanups:**
  - `file_new` and `scope_new` pack their fields onto fewer lines.
  - `file_book`'s Ref guards are flat.
  - `seg_open`, `node_fields`, `val_arms`, `emit_args`, `emit_fork` and
    `emit_row` drop temporaries. In `emit_fork`, `seg_fid` is hoisted to just
    before its first use, so ids are allocated in the same order.
  - `js_var`, `js_call`, `js_expr` and `js_func` share expressions.
  - `c_ids` drops a redundant `!k`.
- **Comments:** the File, Val, Emit, Compile, C and JS headers and a few
  others are shorter and say the same.

## Method: golden diff

1. Took a pristine copy of `bend2/` at origin/main (295e9965), outside the
   repo.
2. For every `tests/**/*.bend` file (1,720 files), ran
   `bun bend2/main.ts t.bend -o out.{c,js,mjs}` from the test's own directory,
   once with the old compiler and once with the new one. That is 5,160 builds
   per side.
3. Compared each emitted file and each captured stdout/stderr/exit code
   byte for byte. Tests that fail to compile must give the same error text.

The original compiler was run twice first to confirm the output is
deterministic.

## Results

- **Golden diff:** 8,016 files compared (2,856 emitted outputs plus the log of
  every run), **0 differ**.
- **Fork test runner:** PASS 136, FAIL 0, SKIP 13, both before and after.
- **Typecheck:** `tsc` under `bend2/pack/tsconfig.json` reports no errors in
  comp.ts, before or after.
- **Smoke tests:** `bun bend2/main.ts --help` runs, and JS builds of
  `tests/base/cmp_native_model` and `tests/base/f32_hypot_range` print their
  expected lines.

## Tokens

| comp.ts | tokens (tiktoken, gpt-3.5-turbo) |
|---|---|
| origin/main | 65,994 |
| this PR | 65,509 |
| saved | **485** |

🤖 Generated with [Claude Code](https://claude.com/claude-code)
