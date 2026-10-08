# Bad CPU type in executable: stale Intel Homebrew on Apple Silicon without Rosetta

A Mac migrated from an Intel machine (or restored from a backup) keeps the old Intel
Homebrew in `/usr/local`. On a recent macOS without Rosetta 2, every tool in
`/usr/local/bin` that is x86_64-only fails:

```
/bin/sh: /usr/local/bin/node: Bad CPU type in executable
```

`arch -x86_64` does not help: there is nothing to translate x86_64 code.
`doctor.sh` finds those binaries, tells you whether Rosetta is present, shows PATH
shadowing and prints the fix.

## How to run

This is a shell-only topic, so there is no Xcode demo project.

1. See your own machine (read-only, changes nothing): `./doctor.sh`
2. See a simulated broken machine: `./tests/run.sh` builds fixture binaries (also real
   x86_64 / arm64 / universal Mach-O files with `clang -arch`) and runs the doctor
   against them.
3. Configuration through environment variables: `ROOT`, `ARM_PREFIX`, `FILE_CMD`, `ROSETTA_PROBE`.

## Diagnose by hand

```bash
uname -m                              # arm64
file /usr/local/bin/node              # Mach-O 64-bit executable x86_64
/usr/bin/arch -x86_64 /usr/bin/true   # fails without Rosetta
which -a node                         # PATH order: /usr/local/bin before /opt/homebrew/bin?
```

## Fix

```bash
/opt/homebrew/bin/brew install node
ln -sf /opt/homebrew/bin/node /usr/local/bin/node   # also npm, npx
# better: brew bundle dump from the old install, then remove the Intel Homebrew
# and put /opt/homebrew/bin first in ~/.zprofile:
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Side effect: hooks that were silently dead start running again, so behaviour may change.

Write-up: https://alexeyhatkevich.blogspot.com
