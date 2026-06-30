# OpenUsage build recipes — run `just` (or `just --list`) to see them all.
#
# The dev workflow shells out to script/build_and_run.sh, which stages a
# signed .app under dist/ and (for `just run`) launches it. `swift build` and
# `swift test` stay as the first-class build/test entrypoints because that is
# what every SwiftPM project uses.

set shell := ["bash", "-uc"]
set dotenv-load

# Default recipe: print the available recipes.
default:
    @just --list

# Debug build (no app bundle, just the executable under .build/).
build:
    swift build

# Release build (no app bundle).
release:
    swift build -c release

# Run the SwiftPM test suite.
test:
    swift test

# Build, sign, and launch the dev app from dist/OpenUsage.app.
run:
    ./script/build_and_run.sh run

# Build, sign, and stage the dev app under dist/ without launching it.
build-app:
    ./script/build_and_run.sh build

# Launch the dev app and stream its logs (Ctrl-C to stop).
logs:
    ./script/build_and_run.sh logs

# Launch the dev app and confirm it is still running one second later.
verify:
    ./script/build_and_run.sh verify

# Kill the running dev app (matches the bundle id used by build_and_run.sh).
kill:
    pkill -x OpenUsage || true

# Remove .build/ and dist/ so the next build is from scratch.
clean:
    rm -rf .build dist

# Build a distributable, Developer ID-signed DMG (script/release.sh).
# Requires CODESIGN_IDENTITY, SPARKLE_PUBLIC_KEY, and OPENUSAGE_VERSION; the
# notarization creds (NOTARY_APPLE_ID/PASSWORD/TEAM_ID) are also required
# unless ALLOW_UNNOTARIZED=1 is set for a local dry run.
release-dmg:
    ./script/release.sh

# Regenerate the prebuilt app icon (assets/AppIcon.prebuilt/) from
# assets/AppIcon.icon. Run this on a Mac whose actool can compile the
# Liquid Glass icon, then commit the regenerated prebuilt files.
compile-icon:
    ./script/compile_icon.sh
