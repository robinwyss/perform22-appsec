#!/bin/bash

DT_TENANT
DT_API_TOKEN
DT_PAAS_TOKEN
KEPTN_DYNATRACE_SERVICE_VERSION=0.18.1

curl -sL https://get.keptn.sh | sudo -E bash
#TODO how to install helm without prompt
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

keptn install --endpoint-service-type=LoadBalancer --use-case=continuous-delivery

KEPTN_ENDPOINT=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/api
KEPTN_API_TOKEN=$(kubectl get secret keptn-api-token -n keptn -ojsonpath='{.data.keptn-api-token}' | base64 --decode)
KEPTN_BRIDGE_URL=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/bridge

keptn auth --endpoint=$KEPTN_ENDPOINT --api-token=$KEPTN_API_TOKEN

wget https://github.com/dynatrace/dynatrace-operator/releases/latest/download/install.sh -O install.sh && sh ./install.sh --api-url "${DT_TENANT}/api" --api-token $DT_API_TOKEN --paas-token $DT_PAAS_TOKEN --cluster-name "keptn-appsec"


keptn create secret dynatrace --scope=dynatrace-service --from-literal="DT_TENANT=$DT_TENANT" --from-literal="DT_API_TOKEN=$DT_API_TOKEN"

helm upgrade --install dynatrace-service\
 -n keptn https://github.com/keptn-contrib/dynatrace-service/releases/download/$KEPTN_DYNATRACE_SERVICE_VERSION/dynatrace-service-$KEPTN_DYNATRACE_SERVICE_VERSION.tgz\
 --set dynatraceService.config.keptnApiUrl=$KEPTN_ENDPOINT --set dynatraceService.config.keptnBridgeUrl=$KEPTN_BRIDGE_URL\
 --set dynatraceService.config.generateTaggingRules=true\
 --set dynatraceService.config.generateProblemNotifications=true\
 --set dynatraceService.config.generateManagementZones=true\
 --set dynatraceService.config.generateDashboards=true\
 --set dynatraceService.config.generateMetricEvents=true