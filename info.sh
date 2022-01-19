#!/bin/bash

KEPTN_BRIDGE_URL=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/bridge
KEPTN_BRIDGE_PW=$(kubectl -n keptn get secret bridge-credentials -o jsonpath="{.data.BASIC_AUTH_PASSWORD}" | base64 --decode)

GIT_URL=http://$(kubectl get svc --namespace gitea gitea-http -ojsonpath='{.status.loadBalancer.ingress[0].hostname}'):3000
GIT_USER=dynatrace
GIT_PASSWORD=dynatrace

cat << EOF
- Keptn Bridge: $KEPTN_BRIDGE_URL
  - User: keptn Password: $KEPTN_BRIDGE_PW
- Git: $GIT_URL
  - User: $GIT_USER Password: $GIT_PASSWORD
EOF
