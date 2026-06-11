 #!/bin/bash
set -exo pipefail

docker load -i "$XDMOD_VERSION.tar" && docker images 

loaded_image="$(docker load -i "$XDMOD_VERSION.tar" | sed 's/Loaded image: //')"
docker run -dt --name "$XDMOD_VERSION" -p 8080:443 "$loaded_image"
docker exec $XDMOD_VERSION bash -c '/root/bin/services start'

#generate certs and copy 
docker exec "$XDMOD_VERSION" bash -c "openssl genrsa -rand /proc/cpuinfo:/proc/filesystems:/proc/interrupts:/proc/ioports:/proc/uptime 2048 > /etc/pki/tls/private/localhost.key"
docker cp tests/ci/scripts/openssl.cnf $XDMOD_VERSION:/root/openssl.cnf

docker exec "$XDMOD_VERSION" bash -c "openssl req -new -key /etc/pki/tls/private/localhost.key -x509 -sha256 -days 365 - set_serial $RANDOM -out /etc/pki/tls/certs/localhost.crt -config /root/openssl.cnf"

docker exec "$XDMOD_VERSION" bash -c '/root/bin/services restart'

docker cp "$XDMOD_VERSION":/etc/pki/tls/certs/localhost.crt .


if [ "$PYTHON_VERSION" = "min-python" ]; then
    pyenv install -s 3.8
    pyenv global 3.8
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
fi


python3 -m pip install --upgrade pip
python3 -m pip install --upgrade flake8 flake8-commas flake8-quotes
python3 -m flake8 . --max-complexity=10 --max-line-length=160 --show-source --exclude __init__.py
python3 -m pip install -e .[report]
python3 -m pip install --upgrade python-dotenv pytest pytest-cov

# The minimum version of each dependency should be tested in the
# container with the minimum Python version.
if [ "$PYTHON_VERSION" = "min-python" ]; then
    
    min_dependency_versions=$(awk \
        '/install_requires/ {flag=1} flag && !/install_requires/ && NF {print $0} flag && /^\[.*\]$/ {flag=0}' \
        setup.cfg | tr -d '\n' | sed 's/ >= /==/g'
    )
    python3 -m pip install --force-reinstall $min_dependency_versions
fi

rest_token=$(
    curl -sS -X POST -c xdmod.cookie -d 'username=normaluser&password=normaluser' https://localhost:8080/rest/auth/login | 
    jq -r '.results.token'
    )

api_token=$(curl -sS -X POST -b xdmod.cookie "https://localhost:8080/rest/users/current/api/token?token=$rest_token" | jq -r '.data.token')

echo "XDMOD_API_TOKEN=$api_token" > ${XDMOD_VERSION}-token

cat "$(pwd)/localhost.crt" >> "$(python3 -c 'import certifi; print(certifi.where())')"

REQUESTS_CA_BUNDLE=localhost.crt XDMOD_API_TOKEN="$api_token" XDMOD_HOST="https://localhost:8080" python3 -m pytest --cov --cov-branch -vvs -o log_cli=true tests/ || true

mv .coverage ".coverage.${PYTHON_VERSION}.${XDMOD_VERSION}"