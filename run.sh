#!/bin/bash
#
# Run zesty-repos scripts in a throwaway SmartOS lx zone
#
# usage: run.sh script.sh [script.sh ...]
#
# The zone is defined by spec.json (see spec.json.sample), which must mount the yum repo root at /yum and this directory
# at /zesty-repos. Scripts run in the order given, stopping at the first failure.

cd "$(dirname "$0")" || exit

set -x
vmadm create -f spec.json || exit $?
id=$(vmadm lookup alias=zesty-repos) || exit $?
rc=0
for script in "$@"; do
    zlogin "$id" "/zesty-repos/${script}" || { rc=$?; break; }
done
vmadm delete "$id"
exit $rc
