{{/* Settings shared by the WordPress pods and the install job. */}}
{{- define "bedrock.env" -}}
- { name: WP_ENV, value: production }
- { name: WP_HOME, value: {{ printf "%s://%s" (ternary "https" "http" (ne .Values.host "")) (default "localhost" .Values.host) | quote }} }
- { name: WP_SITEURL, value: {{ printf "%s://%s/wp" (ternary "https" "http" (ne .Values.host "")) (default "localhost" .Values.host) | quote }} }
# Writes go to the current Galera primary; the operator moves this Service to
# another pod when the primary fails.
- { name: DB_HOST, value: bedrock-db-primary }
- { name: DB_NAME, value: wordpress }
- { name: DB_USER, value: wordpress }
- { name: WP_REDIS_HOST, value: redis }
- { name: S3_UPLOADS_BUCKET, value: {{ printf "%s/%s" .Values.s3.bucket .Values.s3.prefix | quote }} }
- { name: S3_UPLOADS_REGION, value: {{ .Values.s3.region | quote }} }
- { name: S3_UPLOADS_ENDPOINT, value: {{ .Values.s3.endpoint | quote }} }
- { name: S3_UPLOADS_BUCKET_URL, value: {{ printf "https://%s.%s/%s" .Values.s3.bucket (trimPrefix "https://" .Values.s3.endpoint) .Values.s3.prefix | quote }} }
{{- end -}}

{{/* Container hardening required by Pod Security "restricted". */}}
{{- define "bedrock.containerSecurity" -}}
allowPrivilegeEscalation: false
capabilities: { drop: ["ALL"] }
{{- end -}}
