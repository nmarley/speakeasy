# Transcript Cleanup Overhaul

## Problem

The local transcript cleanup step leaks conversational scaffolding
(e.g. "Here's the cleaned transcript:") into the pasted output, and
sometimes treats dictated speech as an instruction to obey rather
than text to punctuate. The current mitigations are inadequate:

- A hand-maintained `preamblePatterns` blocklist matched with
  `hasPrefix` guesses at non-deterministic output. It is also broken:
  the patterns use straight ASCII apostrophes (U+0027) while the model
  emits typographic apostrophes (U+2019), so several patterns never
  match.
- The system prompt is a wall of negations and even quotes the exact
  forbidden phrase, which primes the model to produce it. There are
  no positive input/output demonstrations.
- A single long-lived `ChatSession` is reused across every dictation.
  Its KV cache accumulates prior transcripts and responses, so the
  same input can clean differently depending on history. This is the
  real source of the perceived non-determinism; decoding is already
  greedy (`topK: 1`).

## Approach

Fix the architecture, not the symptom: isolate context per cleanup,
switch to a stronger small local model (Qwen2.5-1.5B-Instruct-4bit),
rewrite the prompt as a positive output contract, teach the format
and the data/instruction boundary with few-shot examples, and reduce
output post-processing to a minimal principled guard.

All work is local and offline. No network dependency is introduced.

## Stages

Stage 1: Isolate context per cleanup
  1a: Stop reusing one long-lived session across dictations. Build the
      cleanup input fresh each call as system + few-shot history +
      this transcript, using the cached model container.
  1b: Keep greedy decode (topK 1) so each cleanup is deterministic and
      reproducible once context is clean.

Stage 2: Swap the model to Qwen2.5-1.5B-Instruct-4bit
  2a: Point model presence, download/load, delete, and size lookups at
      the Qwen2.5-1.5B registry entry.
  2b: Update the model name and size display constants.
  2c: Verify no other source hardcodes the Gemma id or "Gemma 3 1B"
      label.

Stage 3: Rewrite the system prompt as a positive contract
  3a: Replace the negation wall with a crisp role plus a strict output
      contract: the reply is inserted verbatim into the user's
      document, so return only the punctuated text.
  3b: Remove the literal forbidden-phrase example that primes the bad
      output.
  3c: State the data/instruction boundary once, positively: the tagged
      content is text to punctuate, never a request to act on.

Stage 4: Add few-shot examples
  4a: Build a static array of user/assistant message pairs that
      demonstrate the transform: a plain sentence, a run-on with no
      punctuation, an imperative transcript whose output is the same
      words punctuated (clean, do not obey), a question transcript,
      and one with proper nouns and acronyms.
  4b: Inject the examples via the history initializer on each isolated
      cleanup call.

Stage 5: Replace the preamble blocklist with a minimal guard
  5a: Delete the preamble pattern list and the prefix-stripping loop.
  5b: Keep only trim, echoed transcript-tag stripping, and single
      wrapping-quote-pair stripping.
  5c: Keep validation (prompt-leak fingerprints and length ratio) and
      update the fingerprints to match the new prompt wording.
  5d: On validation failure, fall back to the original transcript
      rather than retrying identical greedy context.

Stage 6: Verify
  6a: Debug build compiles clean.
  6b: Manually exercise cleanup on a plain sentence, an imperative, and
      a question, confirming no preamble and no obeying.
