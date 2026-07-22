#!/bin/bash
set -exo pipefail

NETWORK=xdmod-net

declare -A IMAGES=(
    ["xdmod-main-dev"]="tools-ext-01.ccr.xdmod.org/xdmod:xdmod-data-main-dev"
    ["xdmod-11-0-dev"]="tools-ext-01.ccr.xdmod.org/xdmod:xdmod-data-11-0-dev"
    ["xdmod-11-0"]="tools-ext-01.ccr.xdmod.org/xdmod:xdmod-data-11-0"
)

docker network create "$NETWORK" 2>/dev/null || true

# this will pull the images and start containers for each of the XDMoD versions
for v in "${!IMAGES[@]}"; do
    docker rm -f "$v" 2>/dev/null || true
    docker pull --platform linux/amd64 "${IMAGES[$v]}"
    docker run -dt --network "$NETWORK" --name "$v" -e CONTAINER_NAME="$v" "${IMAGES[$v]}"
done


# gives the containers time to start up
for v in "${!IMAGES[@]}"; do
    echo "waiting for $v..."
    timeout 120 bash -c "
        until docker exec $v bash -c \"curl -sk -X POST -d 'username=normaluser&password=normaluser' https://localhost/rest/auth/login | jq -e '.success == true'\" >/dev/null 2>&1; do
            sleep 3
        done
    " || { echo \"ERROR: $v never became ready\"; exit 1; }
    echo "$v ready"
done

echo "All containers up. Now running generation..."


docker run --rm --network xdmod-net \
    -v "$(pwd):/project" -w /project \
    cimg/python:3.14 \
    bash -c "bash ./tests/ci/scripts/regen_generate.sh"

sudo chown -R "$(id -u):$(id -g)" tests/regression/data/
