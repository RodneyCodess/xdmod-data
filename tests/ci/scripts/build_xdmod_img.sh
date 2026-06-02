 #!/bin/bash
set -eo pipefail

XDMOD_VERSION="$1"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=$BASE_DIR/../../..

BASE_IMAGE="tools-ext-01.ccr.xdmod.org/xdmod:x86_64-rockylinux8.9.20231119-v11.0.0-1.0-03"

docker pull $"BASE_IMAGE"

IMAGE_TO_SAVE="$BASE_IMAGE"


if [[ "$XDMOD_VERSION" == "xdmod-main-dev" || "$XDMOD_VERSION" == "xdmod-11-0-dev" ]]; then
    if [ "$XDMOD_VERSION" == 'xdmod-main-dev' ]; then
        branch='main'
    else
        branch="xdmod$(echo $XDMOD_VERSION | sed 's/xdmod-\(.*\)-dev/\1/' | sed 's/-/./')"
    fi

    docker run -dt --name "$XDMOD_VERSION" -h "$XDMOD_VERSION" 
        "$BASE_IMAGE"

    docker exec $XDMOD_VERSION bash -c "git clone --depth=1 --branch=$branch https://github.com/ubccr/xdmod.git /root/xdmod"
    docker exec -w /root/xdmod $XDMOD_VERSION bash -c 'composer install'
    docker exec -w /root/xdmod $XDMOD_VERSION bash -c '/root/bin/buildrpm xdmod'
    # Work around the fact that the 11.0 version of bootstrap.sh contains
    # an extra prompt in xdmod-upgrade.tcl for upgrading from 10.5 to 11.0,
    # and in this case we are upgrading from an earlier version of 11.0 to
    # the latest development version of 11.0, so that prompt should not be
    # expected.
    if [ "$XDMOD_VERSION" == 'xdmod-11-0-dev' ]; then
        docker exec -w /root/xdmod $XDMOD_VERSION bash -c 'sed -i "/^confirmResourceSpecs/d" tests/ci/scripts/xdmod-upgrade.tcl'
    fi
    docker exec -w /root/xdmod $XDMOD_VERSION bash -c 'XDMOD_TEST_MODE=upgrade bash -x ./tests/ci/bootstrap.sh'
    docker exec -w /root/xdmod $XDMOD_VERSION bash -c './tests/ci/validate.sh'

    docker commit "$XDMOD_VERSION" "$XDMOD_VERSION:built"
    IMAGE_TO_SAVE="$XDMOD_VERSION:built"
fi

docker save -o "$PROJECT_DIR/$XDMOD_VERSION.tar" "$IMAGE_TO_SAVE"
# Update the server hostnames and certificates so the Python containers can
# make requests to them.
#docker exec $XDMOD_VERSION bash -c "sed -i 's/localhost/$XDMOD_VERSION/g' /etc/httpd/conf.d/xdmod.conf"
# (Re)start the XDMoD-related services.
#docker exec $XDMOD_VERSION bash -c '/root/bin/services restart'
# Copy the 10,000 users file into the container and shred it.
# We use this file so we can test filters with more than 10,000
# values and date ranges that span multiple quarters.
# docker cp $PROJECT_DIR/tests/ci/artifacts/10000users.log $XDMOD_VERSION:.
# docker exec $XDMOD_VERSION xdmod-shredder -r frearson -f slurm -i 10000users.log
# # Ingest and aggregate.
# date=$(date --utc +%Y-%m-%d)
# docker exec $XDMOD_VERSION xdmod-ingestor --ingest
# docker exec $XDMOD_VERSION xdmod-ingestor --aggregate=job --last-modified-start-date $date
# # Copy certificate (for doing requests) from the XDMoD container.
# #docker cp $XDMOD_VERSION:/etc/pki/tls/certs/$XDMOD_VERSION.crt $PROJECT_DIR