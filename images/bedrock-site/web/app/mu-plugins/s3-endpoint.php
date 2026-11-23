<?php
/**
 * Plugin Name: S3 endpoint (OVH Object Storage)
 * Description: Points humanmade/s3-uploads to the S3-compatible endpoint given by S3_UPLOADS_ENDPOINT.
 */

add_filter('s3_uploads_s3_client_params', function (array $params): array {
    $endpoint = getenv('S3_UPLOADS_ENDPOINT');
    if ($endpoint) {
        $params['endpoint'] = $endpoint;
        $params['use_path_style_endpoint'] = false; // OVH serves anonymous reads on <bucket>.<endpoint> only
    }
    return $params;
});
