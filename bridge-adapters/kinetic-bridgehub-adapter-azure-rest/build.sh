#!/bin/bash

# Stop running the script on an error
set -e

# Build the jar
docker build -f Dockerfile.builder -t kineticdata/bridgehub-adapter-azure-rest-builder:latest .
docker run -v $PWD:/project -w=/project kineticdata/bridgehub-adapter-azure-rest-builder:latest
