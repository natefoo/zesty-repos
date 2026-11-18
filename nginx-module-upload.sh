#!/bin/bash
set -eo pipefail

# build the nginx upload module for the latest stable nginx from the nginx.org repo

# prevents fetching if things already exist, sets -x, etc.
: ${DEVMODE:=false}
# debug logging
: ${DEBUG:=true}

$DEVMODE && set -x

BUILD_ROOT=/build

MODULE_NAME='upload'
MODULE_SRC_URL='https://github.com/natefoo/nginx-upload-module.git'
MODULE_SRC_BRANCH='openssl3'
BUILD_MODULE_URL='https://raw.githubusercontent.com/nginx/pkg-oss/master/build_module.sh'
NGINX_VERSION=

YUM_ROOT='/yum'

CREATE_BUILD_USER=true
BUILD_USER_FROM="$YUM_ROOT"
USER=build
GROUP=build


# include library
. "$(dirname "$0")/zesty-util.sh"


YUM_GPEL="${YUM_ROOT}/el/${EL_VERSION}/${RPM_ARCH}"
NGINX_REPO_URL="https://nginx.org/packages/centos/${EL_VERSION}/${RPM_ARCH}/"


function latest_nginx_version() {
    dnf --quiet --repofrompath="nginx-stable,${NGINX_REPO_URL}" --repo=nginx-stable \
        repoquery --latest-limit=1 --queryformat='%{version}' nginx
}


function check_module_package() {
    # check GPEL (both repo and staging paths) for a module package built for $NGINX_VERSION
    #
    # returns:
    #   0 if rpm for module is found, else 1
    local rpm
    for rpm in "$YUM_GPEL"{,/_staging}/"nginx-module-${MODULE_NAME}-${NGINX_VERSION}+"*.rpm; do
        [ -f "$rpm" ] && return 0
    done
    return 1
}


function stage_module() {
    # build the module with pkg-oss and stage the rpms to GPEL
    log_entry
    local output="${BUILD_ROOT}/build-module-artifacts"
    local src="${BUILD_ROOT}/nginx-module-${MODULE_NAME}-src"
    curl --silent --show-error --fail --location --output build_module.sh "$BUILD_MODULE_URL"
    # build_module.sh cannot clone a branch, but it can build from a directory
    dnf install -y git
    [ -d "$src" ] || git clone --branch "$MODULE_SRC_BRANCH" "$MODULE_SRC_URL" "$src"
    # as root, since it installs build dependencies
    sh build_module.sh -y -n "$MODULE_NAME" -v "$NGINX_VERSION" -o "$output" "$src"
    runas mkdir -p "${YUM_GPEL}/_staging"
    runas cp "$output"/*.rpm "${YUM_GPEL}/_staging"
    log_exit
}


function main() {
    log_entry
    create_build_user
    cd "$BUILD_ROOT"

    NGINX_VERSION="$(latest_nginx_version)"
    [ -n "$NGINX_VERSION" ] || { log error "Unable to determine latest nginx version from ${NGINX_REPO_URL}"; exit 1; }
    log info "nginx latest stable: ${NGINX_VERSION}"

    if check_module_package; then
        log info "nginx-module-${MODULE_NAME} for nginx ${NGINX_VERSION} already staged or deployed"
    else
        stage_module
    fi

    # deploy staging to GPEL, archiving the module built for the previous nginx
    deploy_repo "$YUM_GPEL"
    log_exit
}


main
