#!/bin/bash

# Configuration
KEPTN_DYNATRACE_SERVICE_VERSION=0.18.1
KEPTN_PROJECT_NAME= 
ISTIO_VERSION=1.12.0

GIT_USER=labuser
GIT_REPO=keptn

# Check for environment variables
if [[ ! -v DT_TENANT ]]; then
    echo "DT_TENANT is not set"
fi
if [[ ! -v DT_API_TOKEN ]]; then
    echo "DT_API_TOKEN is not set"
fi
if [[ ! -v DT_PAAS_TOKEN ]]; then
    echo "DT_PAAS_TOKEN is not set"
fi


#TODO how to install helm without prompt
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# install monaco
curl -L https://github.com/dynatrace-oss/dynatrace-monitoring-as-code/releases/download/v1.6.0/monaco-linux-amd64 -o monaco 
chmod +x monaco
mv monaco /usr/local/bin/

# Install keptn
curl -sL https://get.keptn.sh | sudo -E bash
keptn install --endpoint-service-type=LoadBalancer --use-case=continuous-delivery
KEPTN_ENDPOINT=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/api
KEPTN_API_TOKEN=$(kubectl get secret keptn-api-token -n keptn -ojsonpath='{.data.keptn-api-token}' | base64 --decode)
KEPTN_BRIDGE_URL=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/bridge
keptn auth --endpoint=$KEPTN_ENDPOINT --api-token=$KEPTN_API_TOKEN

# Install Istio 
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$KEPTN_DYNATRACE_SERVICE_VERSION TARGET_ARCH=x86_64 sh -
istio-$KEPTN_DYNATRACE_SERVICE_VERSION/bin/istioctl install

# Install Dynatrace Operator
wget https://github.com/dynatrace/dynatrace-operator/releases/latest/download/install.sh -O install.sh && sh ./install.sh --api-url "${DT_TENANT}/api" --api-token $DT_API_TOKEN --paas-token $DT_PAAS_TOKEN --cluster-name "keptn-appsec"

# Configure Dynatrace in keptn
keptn create secret dynatrace --scope=dynatrace-service --from-literal="DT_TENANT=$DT_TENANT" --from-literal="DT_API_TOKEN=$DT_API_TOKEN"
helm upgrade --install dynatrace-service\
 -n keptn https://github.com/keptn-contrib/dynatrace-service/releases/download/$KEPTN_DYNATRACE_SERVICE_VERSION/dynatrace-service-$KEPTN_DYNATRACE_SERVICE_VERSION.tgz\
 --set dynatraceService.config.keptnApiUrl=$KEPTN_ENDPOINT --set dynatraceService.config.keptnBridgeUrl=$KEPTN_BRIDGE_URL\
 --set dynatraceService.config.generateTaggingRules=true\
 --set dynatraceService.config.generateProblemNotifications=true\
 --set dynatraceService.config.generateManagementZones=true\
 --set dynatraceService.config.generateDashboards=true\
 --set dynatraceService.config.generateMetricEvents=true


 # Install gitea
kubectl create namespace gitea
helm install --values gitea-values.yaml gitea gitea-charts/gitea -n gitea
GIT_URL=$(kubectl get svc --namespace gitea gitea-http -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')

GIT_TOKEN=$(curl -v --user labuser:perform22HOT \
    -X POST "$GIT_URL/api/v1/users/labuser/tokens" \
    -H "accept: application/json" -H "Content-Type: application/json; charset=utf-8" \
    -d "{ \"name\": \"API_TOKEN\" }" | jq -r '.sha1')
curl -X POST "$GIT_URL/api/v1/user/repos" \
    -H "accept: application/json" -H "Content-Type: application/json" \
    -H "Authorization:token $GIT_TOKEN" \
    -d "{ \"auto_init\": false, \"default_branch\": \"main\", \"name\": \"$GIT_REPO\", \"private\": false}"

# create keptn project
keptn create project $KEPTN_PROJECT_NAME  --shipyard=./shipyard.yaml --git-user=$GIT_USER --git-token=$GIT_TOKEN --git-remote-url=http://$GIT_URL/$GIT_USER/$GIT_REPO.git
keptn create service simplenode --project=$KEPTN_PROJECT_NAME
# add helm chart for service
keptn add-resource --project=$KEPTN_PROJECT_NAME --service=simplenode --resource=./keptn/simplenode.tgz --resourceUri=helm/simplenode.tgz --all-stages
# add jmx config
keptn add-resource --project=$KEPTN_PROJECT_NAME --stage=staging --service=simplenode --resource=./keptn/jmeter/load.jmx --resourceUri=jmeter/load.jmx
# deploy initial version
keptn trigger delivery --project=$KEPTN_PROJECT_NAME --service=simplenode  --image=docker.io/robinwyss/simplenodeservice --tag=1.0.1

