#!/bin/bash
set -exo pipefail


if [ "$PYTHON_VERSION" = "min-python" ]; then
    pyenv global 3.8
fi

python3 -m pip install --upgrade coverage

ls -la .coverage.* || true

coverage combine .coverage.${PYTHON_VERSION}.*

coverage report -m