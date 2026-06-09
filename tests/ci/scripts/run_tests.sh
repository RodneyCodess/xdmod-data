 #!/bin/bash
set -exo pipefail

docker load -i "$XDMOD_VERSION.tar" && docker images 

loaded_image="$(docker load -i "$XDMOD_VERSION.tar" | sed 's/Loaded image: //')"
docker run -dt --name "$XDMOD_VERSION" -p 8080:443 "$loaded_image"

docker exec $XDMOD_VERSION bash -c '/root/bin/services start'


if [ "$PYTHON_VERSION" = "min-python" ]; then
    pyenv install -s 3.8
    pyenv global 3.8
fi
python3 --version   

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
    curl -k -sS -X POST -c xdmod.cookie -d 'username=normaluser&password=normaluser' https://localhost:8080/rest/auth/login | 
    jq -r '.results.token'
    )

api_token=$(curl -k -sS -X POST -b xdmod.cookie "https://localhost:8080/rest/users/current/api/token?token=$rest_token" | jq -r '.data.token')

echo "XDMOD_API_TOKEN=$api_token" > ${XDMOD_VERSION}-token

XDMOD_HOST="https://localhost:8080" python3 -m pytest --cov --cov-branch -vvs -o log_cli=true tests/ || true

mv .coverage ".coverage.${PYTHON_VERSION}.${XDMOD_VERSION}"

