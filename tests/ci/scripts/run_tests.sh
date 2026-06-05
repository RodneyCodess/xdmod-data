 #!/bin/bash
set -eo pipefail

docker load -i "$XDMOD_VERSION.tar" && docker images 

loaded_image="$(docker load -i "$XDMOD_VERSION.tar" | sed 's/Loaded image: //')"
docker run -dt --name "$XDMOD_VERSION" -p 8080:443 "$loaded_image"

curl -k https://localhost:8080
 
echo "$loaded_image"

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

#pytest --cov=my_project
python3 -m pip freeze 



