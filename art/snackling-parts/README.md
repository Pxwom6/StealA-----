# Snackling model sources

The polished Snackling models, designed in Claude Design (DECISIONS.md #28).

- `prompt-batch-1.md` … `prompt-batch-8.md`: the prompts. Attach one to a new design to redo a batch.
- `batch-1.json` … `batch-3.json`: what the designs produced (format `snackling-parts-1`, described in the
  prompts and at "Imported models" in `src/shared/Logic/CreatureRecipe.luau`).
- `batch-4.json`: the four Winter 2026 Snacklings, built by hand in the same format (checked from every side in an
  offline 3D preview). `prompt-batch-4.md` asks Claude Design for its own take; a design's JSON replaces this file.
- `batch-5.json`: the four Valentine's 2027 Snacklings, hand-built the same way; `prompt-batch-5.md` is its prompt.
- `batch-6.json`: the four Easter 2027 Snacklings, hand-built the same way; `prompt-batch-6.md` is its prompt.
- `batch-8.json`: the four Harvest Feast 2026 Snacklings, hand-built the same way (from a small script that mirrors
  parts, puts eye sets on the head's surface and fits each model into the design box) and checked from five sides,
  next to polished models of their tiers and with mutations, in the offline preview; `prompt-batch-8.md` is its
  prompt.

After changing a batch file, run `lune run tools/importParts.luau` from the repo root. It checks every model and
rewrites `src/shared/Config/CreatureParts.luau`, the generated file the game uses. Then run the tests.
