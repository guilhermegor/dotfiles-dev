# tests/

Unit tests for the repo's bash helpers, written with
[bats-core](https://github.com/bats-core/bats-core).

## Run locally

```bash
sudo apt-get install -y bats   # one-time
bats tests/                    # run the whole suite
bats tests/restore_env_prompt.bats   # one file
```

Or run the full CI workflow locally with `act` (see the `act` skill):

```bash
act -W .github/workflows/tests.yml
```

## What is covered

| File | Unit under test |
|------|-----------------|
| `restore_env_prompt.bats` | `ai_clients/lib/restore_env_prompt.sh` — the restore-`.env` prompt dispatch |

## How the mocking works

`restore_env_prompt.bats` never runs a real restore. Its `setup()`:

1. Defines a stub `print_status` **before** sourcing the helper. The helper only
   sources `lib/common.sh` when `print_status` is undefined, so the stub wins and
   its output is captured for assertions.
2. Points `$HOME` at a sandbox dir → controls the installed-binary branch
   (`$HOME/.local/bin/restore-env.sh`).
3. Reassigns the global `REPO_ROOT` to a sandbox dir → controls the fallback
   branch (`$REPO_ROOT/storage/restore_env.sh`), which the helper reads at call
   time.
4. Drives the `read -rp` prompt by piping a line: `run prompt_restore_env <<< "y"`.

## Adding tests for another helper

Copy the `setup()` pattern, source the target file, stub its I/O boundaries, and
assert on `$status` / `$output` from `run`. Keep each `@test` to one behavior.
