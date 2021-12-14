#!/bin/bash

# Configuration
KEPTN_DYNATRACE_SERVICE_VERSION=0.18.1
KEPTN_PROJECT_NAME= 
ISTIO_VERSION=1.12.0

GIT_USER=labuser
GIT_PASSWORD=!Perform2022@
GIT_DOMAIN=nip.io
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

echo "Installing Monaco"
# install monaco
curl -L https://github.com/dynatrace-oss/dynatrace-monitoring-as-code/releases/download/v1.6.0/monaco-linux-amd64 -o monaco 
chmod +x monaco
mv monaco /usr/local/bin/

echo "Installing Keptn"
# Install keptn
curl -sL https://get.keptn.sh | sudo -E bash
yes | keptn install --endpoint-service-type=LoadBalancer --use-case=continuous-delivery
KEPTN_ENDPOINT=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/api
KEPTN_API_TOKEN=$(kubectl get secret keptn-api-token -n keptn -ojsonpath='{.data.keptn-api-token}' | base64 --decode)
KEPTN_BRIDGE_URL=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/bridge
keptn auth --endpoint=$KEPTN_ENDPOINT --api-token=$KEPTN_API_TOKEN

echo "Installing Istio"
# Install Istio 
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$KEPTN_DYNATRACE_SERVICE_VERSION TARGET_ARCH=x86_64 sh -
istio-$KEPTN_DYNATRACE_SERVICE_VERSION/bin/istioctl install

echo "Installing Dynatrace Operator"
# Install Dynatrace Operator
wget https://github.com/dynatrace/dynatrace-operator/releases/latest/download/install.sh -O install.sh && sh ./install.sh --api-url "${DT_TENANT}/api" --api-token $DT_API_TOKEN --paas-token $DT_PAAS_TOKEN --cluster-name "keptn-appsec"

echo "Cleanup Dynatrace Operator installer"
rm -f install.sh

echo "Configure Dynatrace Service in Keptn"
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

echo "Setup Gitea"
# setup gitea helm yaml
sed -e 's~domain.placeholder~'"$GIT_DOMAIN"'~' \
    -e 's~GIT_USER.placeholder~'"$GIT_USER"'~' \
    -e 's~GIT_PASSWORD.placeholder~'"$GIT_PASSWORD"'~' \
    ./gitea/helm/gitea-values.yaml > gitea-values-gen.yaml

echo "Install Gitea"
 # Install gitea
kubectl create namespace gitea
helm repo add gitea-charts https://dl.gitea.io/charts/
helm install gitea gitea-charts/gitea -f gitea-values-gen.yaml --namespace gitea
GIT_URL=$(kubectl get svc --namespace gitea gitea-http -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')

#echo "Cleanup Gitea install files"
#rm -f gitea-values-gen.yaml

echo "Get Gitea token"
GIT_TOKEN=$(curl -v --user labuser:!Perform2022@ \
    -X POST "$GIT_URL/api/v1/users/labuser/tokens" \
    -H "accept: application/json" -H "Content-Type: application/json; charset=utf-8" \
    -d "{ \"name\": \"API_TOKEN\" }" | jq -r '.sha1')
curl -X POST "$GIT_URL/api/v1/user/repos" \
    -H "accept: application/json" -H "Content-Type: application/json" \
    -H "Authorization:token $GIT_TOKEN" \
    -d "{ \"auto_init\": false, \"default_branch\": \"main\", \"name\": \"$GIT_REPO\", \"private\": false}"

echo "Create Keptn Project"
# create keptn project
keptn create project $KEPTN_PROJECT_NAME  --shipyard=./shipyard.yaml --git-user=$GIT_USER --git-token=$GIT_TOKEN --git-remote-url=http://$GIT_URL/$GIT_USER/$GIT_REPO.git

echo "Create simplenode Service"
keptn create service simplenode --project=$KEPTN_PROJECT_NAME
# add helm chart for service
echo "Add simplenode charts"
keptn add-resource --project=$KEPTN_PROJECT_NAME --service=simplenode --resource=./keptn/simplenode.tgz --resourceUri=helm/simplenode.tgz --all-stages
# add jmx config
echo "Add JMeter test"
keptn add-resource --project=$KEPTN_PROJECT_NAME --stage=staging --service=simplenode --resource=./keptn/jmeter/load.jmx --resourceUri=jmeter/load.jmx
# deploy initial version
echo "Deploy simplenode v1"
keptn trigger delivery --project=$KEPTN_PROJECT_NAME --service=simplenode  --image=docker.io/robinwyss/simplenodeservice --tag=1.0.1

