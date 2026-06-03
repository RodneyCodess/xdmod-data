 #!/bin/bash
set -eo pipefail

XDMOD_VERSION="$1"
PYTHON_VERSION="$2"

docker load -i "$XDMOD_VERSION.tar" && docker images 

loaded_image="$(docker load -i "$XDMOD_VERSION.tar" | sed 's/Loaded image: //')"
docker run -dt --name "$XDMOD_VERSION" -p 8080:443 "$loaded_image"
 
echo "$loaded_image"

