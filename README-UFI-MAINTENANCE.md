# UFI MSM8916 Linux kernel maintenance

This repository records the local UFI001C/MSM8916 changes applied to Linux stable `v6.12.111`. Git metadata is at `C:\Users\Helio\Documents\ufi\.git`; the active WSL worktree is `/home/helio/ufi-build/linux-6.12.111`.

## Upstream and branches

- Upstream remote: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git (official stable repository).
- `v6.12.111`: official stable tag (`e2acc2211022246c77740d5df08265cc27eedcc5`).
- `upstream/linux-6.12.y`: local tracking reference for the official base.
- `ufi/linux-6.12.y`: maintenance branch containing the UFI commits.
- `ufi-v6.12.111`: tag for the verified current tree.

The upstream tag is the first commit. UFI commits are dependency ordered for rebase or cherry-pick onto later 6.12.y tags.

## Current local changes

1. `arm64: dts: qcom: add UFI001C Wi-Fi-only device support` adds the UFI DTS and registers its DTB in the Qualcomm arm64 DTS Makefile. It disables modem/Venus paths, keeps WCNSS, configures USB peripheral mode, LEDs, restart GPIO, and ramoops.
2. `wifi: wcn36xx: guard WCN3620 RX survey and channel metadata` protects the WCN3620 path from unavailable bands, unknown survey frequencies, invalid channels, and false 5 GHz metadata.
3. `configs/ufi-6.12.111-stable.config` records the configuration copied from the verified `config-6.12.111-ufi-diag3-running` file. It is a build input, not an upstream source change.

The old `linux-v6.12.1-msm8916` tree is a separate 6.12.1 project. Images, root filesystems, logs, firmware, archives, and out-of-tree build directories remain outside this kernel repository.

## Build inputs

Existing scripts in `C:\Users\Helio\Documents\ufi` use the WSL source and out-of-tree build directories. The stable build is `build-ufi-6.12.111-stable.sh`; it uses the recorded config and produces `6.12.111-ufi-stable`. No new build command is introduced.

## Exporting patches

Git history is the source of truth. From the WSL worktree run `./scripts/export-patches.sh`, or:

```sh
git format-patch --output-directory patches "$(git merge-base HEAD upstream/linux-6.12.y)..HEAD"
```

`patches/` is ignored and can be regenerated.

## Updating to a later 6.12.y

```sh
git fetch upstream tag v6.12.112
git switch ufi/linux-6.12.y
git switch -c ufi-v6.12.112-rebase
./scripts/update-kernel-base.sh v6.12.112
```

The script refuses a dirty worktree, verifies the target tag, and stops on the first conflict. Resolve it, `git add` the files, and run `git rebase --continue`; use `git rebase --abort` to return to the pre-upgrade state. Inspect `git diff v6.12.112..HEAD`, run the existing build/verification scripts, export patches, and tag the verified result:

```sh
git tag -a ufi-v6.12.112 -m "UFI kernel based on Linux v6.12.112"
```

For cherry-pick migration, create a branch at the new tag and cherry-pick `git log --reverse --format=%H v6.12.111..ufi/linux-6.12.y`, resolving and testing each conflict. The original tag and branch remain rollback points.

## Verification

```sh
git status
git log --oneline --decorate --graph --all
git diff v6.12.111..HEAD --stat
./scripts/export-patches.sh
```

The initial comparison found four worktree entries: the DTS, its Makefile registration, the WCN36xx source change, and a `txrx.c.pre-diag3` backup. The backup is ignored and not part of the patch stack.
