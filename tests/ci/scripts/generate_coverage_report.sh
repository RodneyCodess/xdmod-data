#!/bin/bash
set -exo pipefail


if [ "$PYTHON_VERSION" = "min-python" ]; then
    pyenv install -s 3.8
    pyenv global 3.8
else
    pyenv global 3.14
fi

python3 -m pip install --upgrade coverage

ls -la .coverage.* || true

echo "PYTHON_VERSION IS !!!!! -> : [$PYTHON_VERSION]"

coverage combine .coverage.${PYTHON_VERSION}.*

coverage report -m