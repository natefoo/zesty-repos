#!/bin/bash

cd $(dirname $0)

[ ! -f jq-linux64 ] && curl -LO https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x jq-linux64

set -x
vmadm create -f spec.json || exit $?
id=$(vmadm lookup alias=zesty-repos) || exit $?
zlogin "$id" /zesty-repos/run-slurm-drmaa-inside.sh
vmadm delete "$id"
