 #!/bin/bash
set -eo pipefail

XDMOD_VERSION="$1"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=$BASE_DIR/../../..

BASE_IMAGE="tools-ext-01.ccr.xdmod.org/xdmod:x86_64-rockylinux8.9.20231119-v11.0.0-1.0-03"

docker pull "$BASE_IMAGE"

IMAGE_TO_SAVE="$BASE_IMAGE"

# Generate OpenSSL key and certificate.
docker exec $xdmod_container bash -c "openssl genrsa -rand /proc/cpuinfo:/proc/filesystems:/proc/interrupts:/proc/ioports:/proc/uptime 2048 > /etc/pki/tls/private/$xdmod_container.key"
docker exec $xdmod_container bash -c "openssl req -new -key /etc/pki/tls/private/$xdmod_container.key -x509 -sha256 -days 365 -set_serial $RANDOM -extensions v3_req -out /etc/pki/tls/certs/$xdmod_container.crt -subj '/C=XX/L=Default City/O=Default Company Ltd/CN=localhost' -addext 'subjectAltName=DNS:localhost'"
    

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
    
    #docker commit "$XDMOD_VERSION" "$XDMOD_VERSION:built"
    
else
    docker run -dt --name "$XDMOD_VERSION" -h "$XDMOD_VERSION" "$BASE_IMAGE"
fi

docker exec $XDMOD_VERSION bash -c '/root/bin/services restart'

docker cp $PROJECT_DIR/tests/ci/artifacts/10000users.log $XDMOD_VERSION:.
docker exec $XDMOD_VERSION xdmod-shredder -r frearson -f slurm -i 10000users.log
# Ingest and aggregate.
date=$(date --utc +%Y-%m-%d)
docker exec $XDMOD_VERSION xdmod-ingestor --ingest
docker exec $XDMOD_VERSION xdmod-ingestor --aggregate=job --last-modified-start-date $date

docker commit "$XDMOD_VERSION" "$XDMOD_VERSION:built"
IMAGE_TO_SAVE="$XDMOD_VERSION:built"

docker save -o "$PROJECT_DIR/$XDMOD_VERSION.tar" "$IMAGE_TO_SAVE"
