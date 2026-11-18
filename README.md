# zesty-repos

Automatically build RPMs and maintain up-to-date yum repositories of software, for Enterprise Linux 9 and later.

Each build script checks upstream for new releases, builds RPMs for any that are not already in the repository, and
deploys them. The scripts are meant to run as root in a disposable EL container or zone with the repository root
mounted at `/yum`. A build user is created with the UID and GID that own `/yum`, and builds and repository changes are
made as that user.

| script | builds |
| --- | --- |
| `slurm.sh` | the latest patch release of each Slurm release series on SchedMD's download site, and munge, into a per-package repository for each series |
| `slurm-drmaa.sh` | the latest slurm-drmaa release for each Slurm series that has a repository for this EL version |
| `nginx-module-upload.sh` | the nginx upload module for the latest stable nginx from the nginx.org repository |

## Repository layout

```
/yum/el/<el>/<arch>/                                  # GPEL: Galaxy Packages for Enterprise Linux
/yum/package/<name>/<version>/<el>/<arch>/            # per-package repositories, e.g. one per Slurm version
/yum/package/<name>/<version>/<name>-<version>.repo   # yum .repo file for a per-package repository
/yum/package/<name>/current -> <version>              # per-package version that is also deployed to GPEL
```

New RPMs are first copied to a repository's `_staging/` directory. On deploy, any older RPM with the same package name
is moved to `_archive/`, the staged RPMs are moved into the repository, and the repository metadata is regenerated.

## Running

`run.sh` runs scripts in a disposable SmartOS lx zone defined by `spec.json` (see `spec.json.sample`):

```console
# ./run.sh slurm.sh slurm-drmaa.sh
# ./run.sh nginx-module-upload.sh
```

The scripts can run in any EL container with the same mounts, e.g.:

```console
# docker run --rm -v /path/to/yum:/yum -v $PWD:/zesty-repos rockylinux/rockylinux:9 /zesty-repos/nginx-module-upload.sh
```

## Options

Set in the environment:

| variable | default | description |
| --- | --- | --- |
| `DEBUG` | `true` | Log function entry and exit |
| `DEVMODE` | `false` | Trace commands and reuse previously fetched sources |
| `JQ` | `jq` installed from EL | Path to jq |
