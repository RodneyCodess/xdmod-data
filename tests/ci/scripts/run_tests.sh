 #!/bin/bash
set -eo pipefail

XDMOD_VERSION="$1"
PYTHON_VERSION="$2"

docker load -i "$XDMOD_VERSION.tar" && docker images 

#docker run -dt --name -p 8080:443 "$XDMOD_VERSION:built"