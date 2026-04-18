# Security Policy

Thanks for helping keep Prism and its users safe.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems. Instead,
email **security@prism.plural** (PGP key on request) with:

- A description of the issue and its impact
- Steps to reproduce (or a proof-of-concept)
- Your name/handle if you'd like to be credited

You should get an acknowledgement within 72 hours. We aim to triage and respond
with a plan within 7 days.

## Scope

In scope:

- The Flutter app in this repo
- The sync protocol as implemented by the app (keys, pairing, CRDT merge, relay client)
- The crypto library and relay server (see [prism-sync](https://github.com/prismplural/prism-sync))
- Self-hosted relay deployments following the published guide

Out of scope:

- Social-engineering or phishing against Prism users
- Denial-of-service against a relay you don't operate
- Issues requiring a rooted/jailbroken device or a compromised OS

## Coordinated disclosure

We'll work with you on a fix and a disclosure timeline. Please give us a
reasonable window (typically 90 days) before any public writeup.
