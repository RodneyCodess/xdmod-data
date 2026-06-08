 #!/bin/bash
set -eo pipefail

XDMOD_VERSION="$1"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=$BASE_DIR/../../..

BASE_IMAGE="tools-ext-01.ccr.xdmod.org/xdmod:x86_64-rockylinux8.9.20231119-v11.0.0-1.0-03"

docker pull "$BASE_IMAGE"

IMAGE_TO_SAVE="$BASE_IMAGE"

if [[ "$XDMOD_VERSION" == "xdmod-main-dev" || "$XDMOD_VERSION" == "xdmod-11-0-dev" ]]; then
    if [ "$XDMOD_VERSION" == 'xdmod-main-dev' ]; then
        branch='main'
    else
        branch="xdmod$(echo $XDMOD_VERSION | sed 's/xdmod-\(.*\)-dev/\1/' | sed 's/-/./')"
    fi

    docker run -dt --name "$XDMOD_VERSION" -h "$XDMOD_VERSION" "$BASE_IMAGE"

    docker exec $XDMOD_VERSION bash -c "git clone --depth=1 --branch=$branch https://github.com/ubccr/xdmod.git /root/xdmod"
    docker exec -w /root/xdmod $XDMOD_VERSION bash -c 'composer install'
    docker exec -w /root/xdmod $XDMOD_VERSION bash -c '/root/bin/buildrpm xdmod'
    
    if [ "$XDMOD_VERSION" == 'xdmod-11-0-dev' ]; then
        docker exec -w /root/xdmod $XDMOD_VERSION bash -c 'sed -i "/^confirmResourceSpecs/d" tests/ci/scripts/xdmod-upgrade.tcl'
    fi
    docker exec -w /root/xdmod $XDMOD_VERSION bash -c 'XDMOD_TEST_MODE=upgrade bash -x ./tests/ci/bootstrap.sh'
    
    docker commit "$XDMOD_VERSION" "$XDMOD_VERSION:built"
    IMAGE_TO_SAVE="$XDMOD_VERSION:built"
fi

docker save -o "$PROJECT_DIR/$XDMOD_VERSION.tar" "$IMAGE_TO_SAVE"
