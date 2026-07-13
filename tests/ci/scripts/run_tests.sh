#!/bin/bash
set -exo pipefail

MIN_PYTHON="$(python3 tests/ci/scripts/get_min_python_version.py)"
MAX_PYTHON="3.14"

declare -A XDMOD_HOSTS=(
    ["xdmod-main-dev"]="https://xdmod-main-dev"
    ["xdmod-11.0-dev"]="https://xdmod-11.0-dev"
    ["xdmod-11.0"]="https://xdmod-11.0"
)

for py_version in "$MIN_PYTHON" "$MAX_PYTHON"; do
    if command -v pyenv >/dev/null 2>&1; then
        pyenv install -s "$py_version"
    fi
    python$py_version -m venv /tmp/venv-$py_version
    source /tmp/venv-$py_version/bin/activate

    pip install -e .[report] pytest pytest-cov

    if [ "$py_version" = "$MIN_PYTHON" ]; then

        min_dependency_versions=$(awk \
            '/install_requires/ {flag=1} flag && !/install_requires/ && NF {print $0} flag && /^\[.*\]$/ {flag=0}' \
            setup.cfg | tr -d '\n' | sed 's/ >= /==/g'
        )
        python3 -m pip install --force-reinstall $min_dependency_versions

    fi

    for xdmod_version in "${!XDMOD_HOSTS[@]}"; do
        host="${XDMOD_HOSTS[$xdmod_version]}"

        docker exec "$xdmod_version" bash -c "openssl genrsa -rand /proc/cpuinfo:/proc/filesystems:/proc/interrupts:/proc/ioports:/proc/uptime 2048 > /etc/pki/tls/private/localhost.key"
        docker cp tests/ci/artifacts/openssl.cnf "$xdmod_version":/root/openssl.cnf
        docker exec "$xdmod_version" bash -c "XDMOD_CONTAINER=$xdmod_version openssl req -new -key /etc/pki/tls/private/localhost.key -x509 -sha256 -days 365 -set_serial $RANDOM -out /etc/pki/tls/certs/$xdmod_version.crt -config /root/openssl.cnf"
        docker cp $xdmod_version:/etc/pki/tls/certs/$xdmod_version.crt .

        rest_token=$(curl --cacert "$xdmod_version.crt" -sS -X POST -c xdmod.cookie -d 'username=normaluser&password=normaluser' $host/rest/auth/login | jq -r '.results.token')
        api_token=$(curl --cacert "$xdmod_version.crt" -sS -X POST -b xdmod.cookie "$host/rest/users/current/api/token?token=$rest_token" | jq -r '.data.token')

        echo "XDMOD_API_TOKEN=$api_token" > ~/.xdmod-data-token

        REQUESTS_CA_BUNDLE="$xdmod_version.crt" XDMOD_VERSION="$xdmod_version" XDMOD_HOST="$host" \
            python3 -m pytest --cov --cov-branch --cov-append -vvs -o log_cli=true tests/

    done

    deactivate
done

python3 -m coverage report -m
