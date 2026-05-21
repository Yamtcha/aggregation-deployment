{{/*
Common labels
*/}}
{{- define "fintrack-service.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: fintrack-platform
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{/*
Full image reference — registry/repository:tag
*/}}
{{- define "fintrack-service.image" -}}
{{- printf "%s/%s:%s" .Values.global.imageRegistry .Values.app.image.repository .Values.app.image.tag }}
{{- end }}

{{/*
Init containers — wait for postgres and rabbitmq
*/}}
{{- define "fintrack-service.initContainers" -}}
- name: wait-for-postgres
  image: busybox:1.36
  command: ["sh", "-c", "until nc -z {{ .Values.config.dbHost }} {{ .Values.config.dbPort }}; do echo waiting for postgres; sleep 2; done"]
- name: wait-for-rabbitmq
  image: busybox:1.36
  command: ["sh", "-c", "until nc -z {{ .Values.config.rabbitmqHost }} {{ .Values.config.rabbitmqPort }}; do echo waiting for rabbitmq; sleep 2; done"]
{{- end }}

{{/*
RabbitMQ environment variables
*/}}
{{- define "fintrack-service.rabbitmqEnv" -}}
- name: RABBITMQ_HOST
  valueFrom:
    secretKeyRef:
      name: fintrack-secrets
      key: RABBITMQ_HOST
- name: RABBITMQ_USERNAME
  valueFrom:
    secretKeyRef:
      name: fintrack-secrets
      key: RABBITMQ_USERNAME
- name: RABBITMQ_PASSWORD
  valueFrom:
    secretKeyRef:
      name: fintrack-secrets
      key: RABBITMQ_PASSWORD
- name: SPRING_RABBITMQ_PORT
  value: "5672"
- name: SPRING_RABBITMQ_SSL_ENABLED
  value: "false"
{{- end }}
