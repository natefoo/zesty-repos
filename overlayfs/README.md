# zesty-repos on a remote repo with httpdirfs and fuse-overlayfs

Status: **working prototype, not integrated**. Tested 2026-11-18.

The goal is to run zesty-repos on any host, without the repo being mounted locally from depot. The remote repo is
mounted read-only over HTTP with [httpdirfs](https://github.com/fangfufu/httpdirfs), and a
[fuse-overlayfs](https://github.com/containers/fuse-overlayfs) writable layer goes on top so that zesty sees and
modifies a complete repo. The changes are then published back to depot. This is the same model as the usegalaxy-tools
CVMFS publishing, with httpdirfs in place of the CVMFS client.

`zesty-docker-util.sh` in the repo root has the original 2021 notes from when this did not work.

## Requirements

- **httpdirfs 1.3.x** (1.3.3 tested). 1.2.x, including Debian trixie's 1.2.7, decides nginx does not support range
  requests and exits on the first file read. Until distributions ship 1.3.x it has to be built from source.
- **fuse-overlayfs 1.7 or later** (1.14 tested), which includes containers/fuse-overlayfs#308. Before that, an
  unprivileged copy-up of a read-only lower file failed with EACCES, and httpdirfs presents every file read-only.
- A container with `/dev/fuse`, `CAP_SYS_ADMIN`, and (with AppArmor) `--security-opt apparmor=unconfined`.

Both unprivileged and root mounts work.

## Results

`test.sh` runs the tests below as an unprivileged user and as root.

| operation | result |
| --- | --- |
| list, stat, read | Works. mtimes come from `Last-Modified` and match depot to the second. |
| move a repo RPM to `_archive/` (zesty `archive_rpm`) | Works: copy-up to `_archive/` plus a whiteout. |
| chmod a repo RPM | Works: copy-up. |
| `createrepo_c` with existing `repodata/` | Generates metadata, then aborts copying old `repodata/` files: GIO fails copying their xattrs from httpdirfs. Remove `repodata/` first. |
| `createrepo_c` without existing `repodata/` | Works, but reads (downloads) every RPM to checksum it. |
| `createrepo_c --update --update-md-path <local copy of old repodata/>` | Works, and reads **no** unchanged RPMs: they are matched to the old metadata by size and mtime. |

The upper layer is exactly the changeset, e.g. after archiving one RPM and regenerating metadata:

```
.wh.munge-0.5.18-1.el9.x86_64.rpm            # remove from repo
_archive/munge-0.5.18-1.el9.x86_64.rpm       # add
repodata/.wh..wh..opq                        # replace repodata/ entirely
repodata/{repomd.xml,*-primary.xml.zst,...}  # add
```

## Remaining work

- **zesty integration.** In `deploy_repo`, copy `repodata/` to local storage and remove it, then run
  `createrepo_c --update --update-md-path`.
- **Publishing.** Either:
  - apply the upper layer: copy its files and convert `.wh.<name>` to deleting `<name>` and `.wh..wh..opq` to
    deleting everything else in that directory, or
  - `rsync --delete` from the merged view, which is simpler but sees depot as HTTP does. Symlinks (e.g.
    `package/<name>/current` and the `.repo` links) appear as files and directories and would be replaced by copies,
    files nginx does not list look deleted, and permissions and ownership are not real. Scope each rsync to a
    directory without symlinks, use `-rlt --no-perms --no-owner --no-group`, and check the first run with
    `--dry-run --itemize-changes` (depot's mtimes have sub-second precision, which may need `--modify-window=1`).

  Either way, push RPMs before `repodata/`, using `--delay-updates --delete-after` for `repodata/`, so that clients
  never see a `repomd.xml` that refers to files not yet published. Publishing needs write access to depot, e.g. an SSH
  key restricted with `rrsync`.
