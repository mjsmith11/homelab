#!/bin/bash
set -ex

git pull --recurse-submodules
docker compose down budget-frontend
docker compose down budget-backend
docker compose up --build -d budget-backend
docker compose up --build -d budget-frontend