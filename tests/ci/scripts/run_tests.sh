#!/bin/bash
set -exo pipefail

: "${XDMOD_VERSION:?must be set (see docs/developing.md)}"

: "${VENV:?must be set (see docs/developing.md)}"

# generate cert and copy it out
docker exec "$CONTAINER_NAME" bash -c "openssl genrsa -rand /proc/cpuinfo:/proc/filesystems:/proc/interrupts:/proc/ioports:/proc/uptime 2048 > /etc/pki/tls/private/localhost.key"
docker cp tests/ci/artifacts/openssl.cnf "$CONTAINER_NAME":/root/openssl.cnf
docker exec "$CONTAINER_NAME" bash -c "openssl req -new -key /etc/pki/tls/private/localhost.key -x509 -sha256 -days 365 -set_serial $RANDOM -out /etc/pki/tls/certs/localhost.crt -config /root/openssl.cnf"
docker exec "$CONTAINER_NAME" bash -c '/root/bin/services restart'

# this gives the xdmod-11-0 container a little extra time to start up before we try it with requests,
# otherwise a race condition can cause a connection refused error
# timeout 90 bash -c 'until curl -sf https://localhost:8080 >/dev/null 2>&1; do sleep 1; done'
sleep 30

docker cp "$CONTAINER_NAME":/etc/pki/tls/certs/localhost.crt .

if command -v pyenv >/dev/null 2>&1; then
    pyenv install -s "$PYTHON_VERSION"
    pyenv global "$PYTHON_VERSION"
fi


if [ "$IS_MIN_PYTHON" = "true" ]; then
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
fi

python3 -m venv $VENV
source $VENV/bin/activate

python3 -m pip install --upgrade pip
python3 -m pip install -e .[report]
python3 -m pip install --upgrade python-dotenv pytest pytest-cov

# force-install the oldest supported dependency versions
if [ "$IS_MIN_PYTHON" = "true" ]; then

    min_dependency_versions=$(awk \
        '/install_requires/ {flag=1} flag && !/install_requires/ && NF {print $0} flag && /^\[.*\]$/ {flag=0}' \
        setup.cfg | tr -d '\n' | sed 's/ >= /==/g'
    )
    python3 -m pip install --force-reinstall $min_dependency_versions
fi

# fetch API token
rest_token=$(curl --cacert "localhost.crt" -sS -X POST -c xdmod.cookie -d 'username=normaluser&password=normaluser' https://localhost:$PORT/rest/auth/login | jq -r '.results.token')
api_token=$(curl --cacert "localhost.crt" -sS -X POST -b xdmod.cookie "https://localhost:$PORT/rest/users/current/api/token?token=$rest_token" | jq -r '.data.token')

# write the token where the tests read it
echo "XDMOD_API_TOKEN=$api_token" > ~/.xdmod-data-token

# trust the cert for requests
cat "localhost.crt" >> "$(python3 -c 'import certifi; print(certifi.where())')"

REQUESTS_CA_BUNDLE=localhost.crt XDMOD_HOST="https://localhost:$PORT" python3 -m pytest --cov --cov-branch -vvs -o log_cli=true tests/

mv .coverage ".coverage.${PYTHON_VERSION}.${XDMOD_VERSION}"
