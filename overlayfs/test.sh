#!/bin/bash
#
# Test zesty-repos operations on a remote yum repo mounted with httpdirfs, under a fuse-overlayfs writable layer.
#
# Run in a Debian container with FUSE available, e.g.:
#
#   docker run --rm --device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor=unconfined \
#       -v "$PWD/overlayfs:/t:ro" debian:trixie /t/test.sh
#
set -euo pipefail

: "${REPO_URL:=https://depot.galaxyproject.org/yum/el/9/x86_64/}"
: "${HTTPDIRFS_VERSION:=1.3.3}"     # 1.2.x mistakenly decides nginx does not support range requests

export DEBIAN_FRONTEND=noninteractive
apt-get -qq update >/dev/null
apt-get -qq install -y git meson ninja-build pkg-config gcc libfuse3-dev fuse3 libcurl4-openssl-dev libssl-dev \
    libexpat1-dev libgumbo-dev uuid-dev help2man fuse-overlayfs createrepo-c zstd >/dev/null 2>&1
git clone -q --depth 1 --branch "$HTTPDIRFS_VERSION" https://github.com/fangfufu/httpdirfs.git /src 2>/dev/null
meson setup /src/build /src >/dev/null && ninja -C /src/build >/dev/null
useradd -m tester


cat > /tmp/test-ops.sh <<'EOF'
# zesty deploy operations: a copy-up of a read-only lower file, a mode change, and regenerating metadata
set -euo pipefail
B="$1"
mkdir -p "$B"/{lower,upper,work,merged,cache}
/src/build/httpdirfs -f --cache --cache-location "$B/cache" "$REPO_URL" "$B/lower" > "$B/httpdirfs.log" 2>&1 &
sleep 3
fuse-overlayfs -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/work" "$B/merged"
cd "$B/merged"
lower_count=$(ls -1 ./*.rpm | wc -l)
mkdir -p _staging _archive
archived=$(ls -1 ./*.rpm | head -1)
mv "$archived" _archive/
chmod 644 "$(ls -1 ./*.rpm | head -1)"
# createrepo_c aborts copying old repodata files when it fails to copy their (nonexistent) xattrs from httpdirfs
rm -rf repodata
createrepo_c --quiet --excludes '_*' .
echo "packages: lower=${lower_count} new metadata=$(zstdcat repodata/*primary.xml.zst | grep -c '<package ')"
echo "upper:"; (cd "$B/upper" && find . -mindepth 1 | sort | sed 's/^/  /')
cd /; fusermount3 -u "$B/merged"; fusermount3 -u "$B/lower"
EOF


cat > /tmp/test-update.sh <<'EOF'
# createrepo_c --update reuses metadata for unchanged packages by size and mtime, without reading them
set -euo pipefail
B="$1"
mkdir -p "$B"/{lower,upper,work,merged,cache,old}
/src/build/httpdirfs -f --cache --cache-location "$B/cache" "$REPO_URL" "$B/lower" > "$B/httpdirfs.log" 2>&1 &
sleep 3
fuse-overlayfs -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/work" "$B/merged"
cd "$B/merged"
cp -r repodata "$B/old/" && rm -rf repodata
before=$(du -sb "$B/cache" | cut -f1)
createrepo_c --quiet --update --update-md-path "$B/old" --excludes '_*' .
after=$(du -sb "$B/cache" | cut -f1)
echo "packages: $(zstdcat repodata/*primary.xml.zst | grep -c '<package '), downloaded $(( (after - before) / 1024 )) KiB"
cd /; fusermount3 -u "$B/merged"; fusermount3 -u "$B/lower"
EOF


export REPO_URL
echo "httpdirfs $HTTPDIRFS_VERSION, $(dpkg-query -W -f='${Package} ${Version}, ' fuse-overlayfs createrepo-c)"
for test in ops update; do
    echo "== $test (unprivileged)"; su tester -c "REPO_URL=$REPO_URL bash /tmp/test-${test}.sh /home/tester/${test}"
    echo "== $test (root)"; bash "/tmp/test-${test}.sh" "/root/${test}"
done
