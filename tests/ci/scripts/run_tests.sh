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
    pyenv install -s "$py_version"
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

        rest_token=$(curl --cacert "localhost.crt" -sS -X POST -c xdmod.cookie -d 'username=normaluser&password=normaluser' $host/rest/auth/login | jq -r '.results.token')
        api_token=$(curl --cacert "localhost.crt" -sS -X POST -b xdmod.cookie "$host/rest/users/current/api/token?token=$rest_token" | jq -r '.data.token')

        echo "XDMOD_API_TOKEN=$api_token" > ~/.xdmod-data-token

        XDMOD_VERSION="$xdmod_version" XDMOD_HOST="$host" python3 -m pytest --cov --cov-branch --cov-append -vvs -o log_cli=true tests/

    done




    deactivate
done

python3 -m coverage report -m

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
