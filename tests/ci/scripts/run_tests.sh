 #!/bin/bash
set -eo pipefail

XDMOD_VERSION="$1"
PYTHON_VERSION="$2"

docker load -i "$XDMOD_VERSION.tar" && docker images 

loaded_image="$(docker load -i "$XDMOD_VERSION.tar" | sed 's/Loaded image: //')"
docker run -dt --name "$XDMOD_VERSION" -p 8080:443 "$loaded_image"
 
echo "$loaded_image"

# download python  with uv 

curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.local/bin/env"

uv python install "$PYTHON_VERSION"
uv venv --python "$PYTHON_VERSION"
source .venv/bin/activate

#check python version 
python --version