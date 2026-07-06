#!/bin/bash
set -exo pipefail

: "${BASE_IMAGE:?BASE_IMAGE must be set (see docs/developing.md)}"
: "${XDMOD_VERSION:?XDMOD_VERSION must be set (see docs/developing.md)}"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=$BASE_DIR/../../..

docker run -dt --name "$CONTAINER_NAME" -p $PORT:443 "$BASE_IMAGE"

if [[ "$XDMOD_VERSION" =~ xdmod-.+-dev ]]; then
    if [ "$XDMOD_VERSION" == 'xdmod-main-dev' ]; then
        branch='main'
    else
        branch="xdmod$(echo $XDMOD_VERSION | sed 's/xdmod-\(.*\)-dev/\1/' | sed 's/-/./')"
    fi

    docker exec $CONTAINER_NAME bash -c "git clone --depth=1 --branch=$branch https://github.com/ubccr/xdmod.git /root/xdmod"
    docker exec -w /root/xdmod $CONTAINER_NAME bash -c 'composer install'
    docker exec -w /root/xdmod $CONTAINER_NAME bash -c '/root/bin/buildrpm xdmod'

    # Work around the fact that the 11.0 version of bootstrap.sh contains
    # an extra prompt in xdmod-upgrade.tcl for upgrading from 10.5 to 11.0,
    # and in this case we are upgrading from an earlier version of 11.0 to
    # the latest development version of 11.0, so that prompt should not be
    # expected.
    if [ "$XDMOD_VERSION" == 'xdmod-11-0-dev' ]; then
        docker exec -w /root/xdmod $CONTAINER_NAME bash -c 'sed -i "/^confirmResourceSpecs/d" tests/ci/scripts/xdmod-upgrade.tcl'
    fi
    docker exec -w /root/xdmod $CONTAINER_NAME bash -c 'XDMOD_TEST_MODE=upgrade bash -x ./tests/ci/bootstrap.sh'
fi

docker exec $CONTAINER_NAME bash -c '/root/bin/services restart'

# Copy the 10,000 users file into the container and shred it.
# We use this file so we can test filters with more than 10,000
# values and date ranges that span multiple quarters
docker cp $PROJECT_DIR/tests/ci/artifacts/10000users.log $XDMOD_VERSION:.
docker exec $CONTAINER_NAME xdmod-shredder -r frearson -f slurm -i 10000users.log

# Ingest and aggregate.
date=$(date -u +%Y-%m-%d)
docker exec $CONTAINER_NAME xdmod-ingestor --ingest
docker exec $CONTAINER_NAME xdmod-ingestor --aggregate=job --last-modified-start-date $date
