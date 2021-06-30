# zesty-repos Docker function library


# The problem is, you don't want to (or can't) run docker containers on the server serving your repo, but the repo needs
# to exist in order for you to run e.g. yum `createrepo`. Mirroring down the entire repo in order to do it is a
# non-starter. OverlayFS like CVMFS would be nice but you need to "mount" the repo in order to do it. Two options I
# found for that:
#
#   maintained:   https://github.com/fangfufu/httpdirfs
#   unmaintained: https://github.com/Kurocon/HTTPfs
#
# I never got fuse-overlayfs working correctly inside docker, here is my note in usegalaxy-tools/.ci/jenkins.sh:
#
# Attempting to create files as root yields EPERM, even with allow_root/allow_other and user_allow_other
# FIXME: unprivilged would be preferable but file creation inside docker fails with fuse-overlayfs
#log_exec fuse-overlayfs \
#    -o "lowerdir=${OVERLAYFS_LOWER},upperdir=${OVERLAYFS_UPPER},workdir=${OVERLAYFS_WORK},allow_root" \
#    "$OVERLAYFS_MOUNT"
#
# You also don't have the processing of deletions, mode changes, etc., but you can do that (maybe steal from CVMFS?)
#
# Tested fuse-overlayfs on top of httpdirfs outside docker and got EOPNOTSUPP with the buster fuse-overlayfs and EPERM
# with git fuse-overlayfs. Could try to figure out why but it seems like fuse on fuse is maybe not really great
# (although CVMFS works but they're using the kernel OverlayFS, not fuse)
