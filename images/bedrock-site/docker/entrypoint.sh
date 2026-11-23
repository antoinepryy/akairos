#!/bin/sh
# Sensitive settings (DB password, salts, S3 keys) come as environment
# variables from the Kubernetes Secret bedrock-env (envFrom), never from git.
set -e

# Warm-up: load the home page once Apache is up, then report ready (see healthz.php).
rm -f /tmp/warm
(
  for _ in $(seq 1 60); do
    curl -s -o /dev/null -m 30 http://localhost:8080/ && break
    sleep 1
  done
  touch /tmp/warm
) &

exec docker-php-entrypoint "$@"
