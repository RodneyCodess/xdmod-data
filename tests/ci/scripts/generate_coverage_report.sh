#!/bin/bash
set -exo pipefail

: "${PYTHON_VERSION:?PYTHON_VERSION must be set (see tests/ci/scripts/manual.env)}"

python3 -m pip install --upgrade coverage

python3 -m coverage combine .coverage.${PYTHON_VERSION}.*
python3 -m coverage report -m --fail-under=100
