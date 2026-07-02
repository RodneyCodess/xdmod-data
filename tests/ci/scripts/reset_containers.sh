#!/bin/bash
# Remove any leftover xdmod containers (local testing only — not needed in CI,
# where each job runs on a fresh machine).
docker rm -f $(docker ps -aq --filter "name=xdmod") 2>/dev/null || true
