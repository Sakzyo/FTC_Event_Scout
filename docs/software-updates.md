# Software updates

FTC Event Scout uses Sparkle 2.10.0 for native update checks, signed archive verification before extraction, app replacement, and relaunch. Settings and the app menu share one updater. Automatic-check and automatic-install preferences are managed by Sparkle. The app waits for its Python backend to exit before allowing termination, including Install and Relaunch and installation on quit. Credentials, tags, caches, and preferences remain outside the replaced app bundle.

## Signing setup

The repository contains only the public Ed25519 key in `config/sparkle-public-key.txt`. Its private key is stored in the release Mac's login Keychain under the account `org.ftceventscout.app`. Keep the private key safe and backed up securely; never commit or upload it. The Sparkle tools are downloaded by `swift package resolve` into `.build/artifacts/sparkle/Sparkle/bin`.

For a new release machine, securely transfer the existing signing key using Sparkle's documented key export/import procedure. Generating a different key will prevent updates to already distributed copies. To print the existing public key without exporting private material:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account org.ftceventscout.app -p
```

`FTC_SCOUT_SPARKLE_KEY_ACCOUNT` selects a different Keychain account for update packaging. `FTC_SCOUT_SPARKLE_PUBLIC_KEY` overrides the bundled public key for an explicitly separate development channel. Archive creation refuses to proceed if the signing key does not match the app's public key.

Developer ID signing and notarization are recommended for public distribution. This Mac currently has no valid code-signing identity, so local validation uses the existing ad-hoc signing workflow. When a Developer ID Application identity and a `notarytool` Keychain profile are installed, set `FTC_SCOUT_CODESIGN_IDENTITY` and `FTC_SCOUT_NOTARYTOOL_PROFILE`. The app packaging script signs nested Sparkle code before the enclosing app, submits the finished app for notarization, and staples the ticket before update archiving. Notarization credentials and private keys do not belong in the repository.

## Release pipeline

Choose a new display version and a strictly increasing internal build number. The defaults remain 1.0.4/build 5; integrating the updater does not itself publish or rename a release. For example, a first Sparkle-enabled release could use:

```sh
export FTC_SCOUT_APP_VERSION=1.0.5
export FTC_SCOUT_APP_BUILD=6
./script/package_app.sh release
./script/package_update.sh
./script/package_dmg.sh
```

`package_update.sh` consumes the finalized `dist/FTC Event Scout.app`; it does not rebuild or modify it. It creates `dist/updates/FTC-Event-Scout-1.0.5.zip` and `dist/updates/appcast.xml`, then verifies the archive's Ed25519 signature using Sparkle's official tools. `package_dmg.sh` preserves the existing first-install/legacy migration distribution path and emits its SHA-256 checksum. Use the same signing/notarization environment for both packaging commands.

Upload the ZIP, `appcast.xml`, DMG, and DMG checksum to the matching stable GitHub Release. The default archive URL uses `v` followed by the display version; `FTC_SCOUT_RELEASE_TAG` overrides that tag when needed. Publish the feed only together with its referenced archive. The app's stable feed URL is:

```text
https://github.com/Sakzyo/FTC_Event_Scout/releases/latest/download/appcast.xml
```

The first Sparkle-enabled release must include a DMG because published 1.0.4 copies only understand the old DMG updater. After users install that transition release, future updates use the signed ZIP inside the app. Keep `org.ftceventscout.app` and the installed app name stable.

## Local verification

Run the Swift and Python suites and package the app to validate actual framework embedding and code signatures:

```sh
swift test
python3 -m unittest discover -s tests -p 'test_*.py'
./script/package_app.sh debug
```

A complete update test needs two separate packaged app copies with the same test bundle identifier and increasing build numbers. Give only those debug copies a local feed, serve the signed update, then use the app's Check for Updates and Install and Relaunch controls. The production bundle identifier and installed app should be left untouched. A debug build may explicitly use `FTC_SCOUT_UPDATE_FEED_URL=http://127.0.0.1:18765/appcast.xml`; release packaging rejects loopback feeds and requires HTTPS.

To archive a finalized test copy without rebuilding:

```sh
FTC_SCOUT_UPDATE_DIR="$PWD/.build/update-verification/feed" \
FTC_SCOUT_UPDATE_DOWNLOAD_URL_PREFIX=http://127.0.0.1:18765/ \
./script/package_update.sh "/absolute/path/to/test/FTC Event Scout.app"
```

Verify version/build replacement, relaunch, backend exit, unchanged saved data, and rejection of a modified archive. An ad-hoc local update test does not establish notarized distribution behavior. Public-feed availability and a Developer ID/notarized update still require testing after release setup.

## Verification performed on 19 October 2026

- Swift suite: 68 tests passed. Python suite: 15 tests passed. Shell syntax checks passed.
- The packaged debug app loaded its embedded Sparkle framework; the release app's nested code signatures verified.
- An isolated test bundle updated through the native Sparkle UI from 1.0.4/build 5 to 1.0.5/build 6 and relaunched. The old app and Python backend processes exited. Saved Application Support file hashes remained unchanged.
- A 1.0.6/build 7 test ZIP was modified after signing. The app displayed “The update is improperly signed and could not be validated” and remained on 1.0.5/build 6.
- Both automatic-update preferences survived quitting and reopening the isolated test app. Those test preferences were restored to off afterwards.
- Independent code review found no actionable issues.
- A local 1.0.5/build 6 release candidate, signed update ZIP, appcast, and transition DMG were prepared. These artifacts have not been uploaded. The repository's default version/build values remain unchanged.
- Developer ID signing, notarization, and a published production-feed update remain unverified because the signing identity and production release are not set up.

## References

- [Sparkle setup and signing](https://sparkle-project.org/documentation/)
- [SwiftUI integration](https://sparkle-project.org/documentation/programmatic-setup/)
- [Publishing signed updates](https://sparkle-project.org/documentation/publishing/)
