#!/bin/bash
set -exo pipefail

: "${VENV:?must be set (see docs/developing.md)}"

python3 -m pip install --upgrade coverage

python3 -m coverage combine .coverage.${PYTHON_VERSION}.*
python3 -m coverage report -m --fail-under=100
