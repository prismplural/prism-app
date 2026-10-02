# AI contribution policy

> AI assistance is welcome here. We use it a lot ourselves. Please understand what you're submitting, follow the repository's conventions, and write your PR description and comments yourself.

## Follow the codebase

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the guidance near the code you're changing. Look at how similar problems are already handled in the repository. Those conventions apply whether you write the patch by hand or use an agent.

Keep the change scoped to the problem. A bug fix usually doesn't need a new subsystem, another library, or a rewrite of the surrounding code. If a larger change really is needed, explain why and discuss it with us first. Don't include extra features or cleanup just because a tool suggested them.

## Understand the fix

Read the whole diff. Make sure you understand why the problem happens, how the change fixes it, and what else it could affect. Run the relevant checks and verify what they actually tested. Be able to explain the change and respond to review questions yourself.

It's fine to be learning or unsure about something. Say where you need help. Don't pass along a patch you haven't understood and leave that work to the reviewer. An AI saying the code looks correct doesn't establish that it works.

## [Don't be a meat proxy](https://gruhn.me/blog/2026-08-03/)

Write your PR description, issues, and review comments yourself. Say what you changed, why, and what you checked, in your own words. A few clear sentences are enough; we don't need an agent's report or a generated summary of the diff. Engage with review feedback yourself instead of relaying messages between a reviewer and an agent.

If you're learning with an agent, ask it to explain the change. Then read the code yourself and write the description from your own understanding.

## Tell us what you used

The PR template has a checkbox for AI assistance. If you used it, check the box and list the model and harness (the tool or environment running it), for example `[model name] via [tool name]`. If you don't know the model, say so. A short line is enough; no prompt logs are needed.

## Protect private data

Use synthetic data for reproductions and tests. Don't put real member profiles, chats, exports, keys, tokens, recovery phrases, or private security reports into AI prompts or public contributions. Follow the repository's existing license and attribution requirements for anything you submit.
