# Third-party notices

## AI Town upstream

This project is based on `mewamew/my_ai_town`. The upstream repository states that a unified root license is still being prepared. Do not assume that the whole source tree or its assets have a permissive redistribution license.

Upstream: <https://github.com/mewamew/my_ai_town>

## unlimited-ai-first

The desktop integration invokes the unmodified files `src/context.js` and `src/prompts.js` from the pinned Git submodule. It also reproduces the `MODEL_RUNTIME_INJECTION` text from `src/worker.js` in the local bridge adapter:

- Repository: <https://github.com/guyue12120924-coder/unlimited-ai-first>
- Commit: `64409d7ad930e7ff5948f2c15764c440741d01ae`
- License: `vendor/unlimited-ai-first/LICENSE`

The AI Town-specific JSON decision, memory-extraction, continuity, and model-fallback adapters live outside the submodule. The upstream license prohibits unauthorized modification, adaptation, reverse engineering, and commercial use; because the local integration combines upstream material with new adapters, do not redistribute or use it commercially unless you have confirmed that the required authorization covers this use. Any authorized distribution must retain visible attribution and the upstream license.
