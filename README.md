# Prism Plural

Prism is an app for plural systems: keep member profiles, log who's fronting, and give your system a place to talk, make decisions, and keep track of daily life. We're a plural system building Prism and using it every day.

Prism works locally without an account and stores your records in an encrypted database. Optional device sync uses hybrid post-quantum end-to-end encryption. You can also host your own relay.

**[Download Prism](https://prismplural.com/download/)** · [User guide](https://prismplural.com/docs/) · [What's new](https://prismplural.com/updates/) · [Discord](https://discord.gg/32Qfhd6jMM)

Prism is in beta on iOS, Android, macOS, Linux, and Windows. There are rough edges. The download page has the current builds and installation instructions.

## What you can do

- **Keep track of your members.** Profiles, groups, custom fields, pronouns, and avatars, with room for as much or as little detail as you want.
- **Log fronting.** Record who's fronting or co-fronting, add notes, and look back through your system's history.
- **Talk within your system.** Chat, direct messages, message boards, polls, photos, and voice notes.
- **Keep daily things together.** Notes, habits, reminders, and sleep tracking. Features you turn off disappear from the interface; their data is kept.
- **Bring your existing data.** Import saved Simply Plural exports or PluralKit data. PluralKit also has ongoing bidirectional sync. The [import guide](https://prismplural.com/docs/import/) explains what transfers and what doesn't.

## Your data

Local use doesn't require a network connection. If you enable device sync, your devices encrypt and decrypt content. The relay stores encrypted content and handles delivery; it can see metadata such as device membership, public keys, and the sizes and timing of transfers.

The app has no third-party analytics or engagement tracking. The public relay collects operational metrics and logs to keep the service running.

You can use the Prism relay or [self-host one](https://github.com/prismplural/prism-sync/blob/main/self-host/SELF-HOSTING.md). [Encryption details](https://prismplural.com/docs/encryption-details/) and [privacy information](https://prismplural.com/docs/privacy/) cover the details and boundaries.

## Work on Prism

This repository contains the Flutter app and its native image codec. The Rust sync engine, Dart bindings, and relay live in [prism-sync](https://github.com/prismplural/prism-sync).

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for a local build, the code layout, and the checks to run for your change. You can also help by reporting a bug, checking accessibility, or fixing an unclear instruction.

For bugs and feature ideas, [open an issue](https://github.com/prismplural/prism-app/issues). Include the app version, platform, and what happened. Please remove personal system data from screenshots and logs. For questions about using the app, the [user guide](https://prismplural.com/docs/) and [Discord](https://discord.gg/32Qfhd6jMM) are good places to start. Report security problems privately through [SECURITY.md](SECURITY.md).

## AI use

We use local and hosted AI tools extensively in development. We accept AI-assisted contributions, but expect the contributor to be responsible for understanding and checking the work. Our [AI policy](AI_POLICY.md) spells out the expectations for code, documentation, reports, and review.

## License

[GNU Affero General Public License v3.0](LICENSE), with the additional permission for app store distribution included in that file.
