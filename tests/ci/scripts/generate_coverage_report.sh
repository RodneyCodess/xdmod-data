#!/bin/bash
set -exo pipefail

python3 -m pip install --upgrade coverage

python3 -m coverage combine .coverage.${PYTHON_VERSION}.*
python3 -m coverage report -m --fail-under=100
