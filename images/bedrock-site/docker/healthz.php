<?php
// Ready only once the container has served a first WordPress page (OPcache warm),
// so Swarm and Traefik never send traffic to a cold container. Does not touch MySQL itself.
if (is_file('/tmp/warm')) {
    echo 'ok';
} else {
    http_response_code(503);
    echo 'warming up';
}
