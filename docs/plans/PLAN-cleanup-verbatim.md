# Transcript Cleanup: Verbatim Preservation

## Problem

The local cleanup model omits words, especially profanity, and
occasionally replaces a word with a different one (for example,
"infra" becomes "infrastructure"). The cleanup step's only authorized
transformations are punctuation and capitalization. Omission and
substitution are never acceptable.

The current validation only checks the output/input length ratio
(0.5 to 1.5), so a dropped or substituted word passes. The system
prompt says to keep every original word, but nothing enforces it and
no example demonstrates preservation of slang, abbreviations, or
profanity.

## Approach

Make preservation mechanically guaranteed, then make the model more
likely to comply so the guarantee rarely triggers a fallback.

1. Normalize both the transcript and the model output by lowercasing
   and keeping only Unicode alphanumerics, then require exact
   equality. Case, punctuation, apostrophes, hyphens, and whitespace
   are free. Any dropped, added, substituted, or reordered word
   rejects the output and the raw transcript is used instead.

2. State the preservation contract in the system prompt and add
   few-shot examples that demonstrate it, including profanity kept
   verbatim and abbreviations left unexpanded. Existing examples that
   only change capitalization (Terraform, EKS, PR, GitHub) stay, since
   case changes are part of the job.

3. Add a debug-only probe that runs fixed transcripts through the real
   model, so any model swap is decided by data. If the model still
   censors or rewrites content, switch to a stronger local model.

Strict preservation keeps stutters. Allowing stutter removal would
return judgment to the model, which is the source of the current
problem. A stutter exception would need its own guarded design and is
out of scope.

The guarantee covers the cleanup stage. Words missing from the raw
Whisper transcript itself are out of scope.

## Stages

Stage 1: Guarantee verbatim content preservation
  1a: Extract the pure cleanup contract (system prompt, few-shot
      pairs, output sanitizing, validation, content normalization)
      into a Foundation-only CleanupContract library target that the
      app depends on.
  1b: Add normalized content comparison and reject any output whose
      normalized content differs from the input's, replacing the
      length-ratio check.
  1c: Keep the empty-output and prompt-leak checks and the fallback
      to the raw transcript on rejection.
  1d: Add a CleanupContractTests target covering normalization edge
      cases, dropped/substituted/added/reordered words, and an
      invariant that every few-shot assistant reply preserves its
      user transcript.
  1e: Add a test recipe to the macOS justfile.

Stage 2: Harden the prompt and demonstrations
  2a: State the preservation contract in the system prompt: only
      punctuation and capitalization may change; never expand,
      contract, or replace words; every word appears exactly once, in
      order, spelled exactly as dictated, including slang,
      abbreviations, names, and profanity.
  2b: Keep the capitalization examples and add pairs showing
      profanity kept verbatim and abbreviations left unexpanded.
  2c: Update the prompt-leak fingerprints to the new prompt wording.
  2d: Run the unit tests, including the few-shot invariant.

Stage 3: Verify against the real model
  3a: Add a debug-only CLI probe that runs a fixed transcript list
      through the loaded model and reports pass or fallback for each.
  3b: Run the probe on profanity, abbreviations, a run-on, an
      imperative, and a question. Keep the current model if every
      probe preserves content.
  3c: If any probe shows censorship or rewriting, switch the registry
      entry to a stronger local model, update the display constants,
      and re-run the probe.
