# Snackling model sources

The polished Snackling models, designed in Claude Design (DECISIONS.md #28).

- `prompt-batch-1.md` … `prompt-batch-3.md`: the prompts. Attach one to a new design to redo a batch.
- `batch-1.json` … `batch-3.json`: what the designs produced (format `snackling-parts-1`, described in the
  prompts and at "Imported models" in `src/shared/Logic/CreatureRecipe.luau`).

After changing a batch file, run `lune run tools/importParts.luau` from the repo root. It checks every model and
rewrites `src/shared/Config/CreatureParts.luau`, the generated file the game uses. Then run the tests.
