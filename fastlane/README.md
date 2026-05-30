fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight, distribute to the Prism Private Beta group

### ios sideload

```sh
[bundle exec] fastlane ios sideload
```

Build unsigned sideload IPA and upload it to the GitHub release

----


## Mac

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Build and upload to TestFlight, distribute to the Prism Private Beta group

### mac sideload

```sh
[bundle exec] fastlane mac sideload
```

Build signed/notarized Developer ID DMG and upload it to the GitHub release

----


## Android

### android beta

```sh
[bundle exec] fastlane android beta
```

Build and upload to the Play Store closed beta testing track

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
