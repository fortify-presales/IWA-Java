#!/bin/sh
echo "Running IWA container"
docker run --rm --name iwa -d -p 8080:8080 iwa:latest
docker logs --follow iwa
