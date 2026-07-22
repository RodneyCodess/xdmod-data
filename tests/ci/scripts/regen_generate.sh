#!/bin/bash
set -exo pipefail

python3 -m pip install --user '.[report]' pytest pytest-cov python-dotenv
export PATH="$HOME/.local/bin:$PATH"

declare -A XDMOD_HOSTS=(
    ["xdmod-main-dev"]="https://xdmod-main-dev"
    ["xdmod-11-0-dev"]="https://xdmod-11-0-dev"
    ["xdmod-11-0"]="https://xdmod-11-0"
)

for xdmod_version in "${!XDMOD_HOSTS[@]}"; do
    host="${XDMOD_HOSTS[$xdmod_version]}"

    timeout 60 bash -c "until curl -k -sf https://$xdmod_version/localhost.crt -o $xdmod_version.crt; do sleep 2; done" \
        || { echo "ERROR: cert never came for $xdmod_version"; exit 1; }

    rest_token=""
    for attempt in $(seq 1 30); do
        rest_token=$(curl --cacert "$xdmod_version.crt" -sS -X POST -c xdmod.cookie \
            -d 'username=normaluser&password=normaluser' "$host/rest/auth/login" | jq -r '.results.token')
        [ -n "$rest_token" ] && [ "$rest_token" != "null" ] && break
        sleep 2
    done

    api_token=$(curl --cacert "$xdmod_version.crt" -sS -X POST -b xdmod.cookie \
        "$host/rest/users/current/api/token?token=$rest_token" | jq -r '.data.token')

    echo "XDMOD_API_TOKEN=$api_token" > ~/.xdmod-data-token

    GENERATE_DATA_FILES=1 REQUESTS_CA_BUNDLE="$xdmod_version.crt" \
        XDMOD_VERSION="$xdmod_version" XDMOD_HOST="$host" \
        python3 -m pytest -vs tests/regression/
done
