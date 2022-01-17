#!/bin/bash

# Configuration
KEPTN_DYNATRACE_SERVICE_VERSION=0.19.0
KEPTN_DYNATRACE_SERVICE_SLI_VERSION=0.12.1
KEPTN_PROJECT_NAME=appsec
ISTIO_VERSION=1.12.0


GIT_USER=dynatrace
GIT_PASSWORD=dynatrace
GIT_DOMAIN=nip.io
GIT_REPO=keptn

export GIT_REPO=keptn

# Check for environment variables
if [[ ! -v DT_TENANT ]]; then
    echo "DT_TENANT is not set"
    exit 0
fi
if [[ ! -v DT_API_TOKEN ]]; then
    echo "DT_API_TOKEN is not set"
    exit 0
fi
if [[ ! -v DT_PAAS_TOKEN ]]; then
    echo "DT_PAAS_TOKEN is not set"
    exit 0
fi

#TODO how to install helm without prompt
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "Installing Monaco"
# install monaco
curl -L https://github.com/dynatrace-oss/dynatrace-monitoring-as-code/releases/download/v1.6.0/monaco-linux-amd64 -o monaco 
chmod +x monaco
mv monaco /usr/local/bin/

echo "Installing Istio"
# Install Istio 
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION TARGET_ARCH=x86_64 sh -
yes | istio-$ISTIO_VERSION/bin/istioctl install

echo "Installing Keptn"
# Install keptn
curl -sL https://get.keptn.sh | sudo -E bash
yes | keptn install --endpoint-service-type=LoadBalancer --use-case=continuous-delivery

# create archive for simplenode chart
tar -C keptn/ -czvf simplenode.tgz charts/

echo "Wait 1 minute to ensure Ingress is created"
sleep 2m 

KEPTN_ENDPOINT=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/api
KEPTN_API_TOKEN=$(kubectl get secret keptn-api-token -n keptn -ojsonpath='{.data.keptn-api-token}' | base64 --decode)
KEPTN_BRIDGE_URL=http://$(kubectl get svc -n keptn api-gateway-nginx -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')/bridge
keptn auth --endpoint=$KEPTN_ENDPOINT --api-token=$KEPTN_API_TOKEN

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
 --set dynatraceService.config.generateProblemNotifications=false\
 --set dynatraceService.config.generateManagementZones=true\
 --set dynatraceService.config.generateDashboards=true\
 --set dynatraceService.config.synchronizeDynatraceServices=false\
 --set dynatraceService.config.generateMetricEvents=true

echo "Install Gitea"
 # Install gitea
kubectl create namespace gitea
helm repo add gitea-charts https://dl.gitea.io/charts/
helm install gitea gitea-charts/gitea -f ./gitea/helm/gitea-values-live.yaml --namespace gitea

echo "Wait 1 minute to ensure Ingress is created"
sleep 5m 

export GIT_URL=$(kubectl get svc --namespace gitea gitea-http -ojsonpath='{.status.loadBalancer.ingress[0].hostname}'):3000

#echo "Cleanup Gitea install files"
#rm -f gitea-values-gen.yaml

echo "Get Gitea token"
export GIT_TOKEN=$(curl -v --user dynatrace:dynatrace -X POST "$GIT_URL/api/v1/users/labuser/tokens" -H "accept: application/json" -H "Content-Type: application/json; charset=utf-8" -d "{ \"name\": \"API_TOKEN\" }" | jq -r '.sha1')
curl -X POST "$GIT_URL/api/v1/user/repos" -H "accept: application/json" -H "Content-Type: application/json" -H "Authorization:token $GIT_TOKEN" -d "{ \"auto_init\": false, \"default_branch\": \"main\", \"name\": \"$GIT_REPO\", \"private\": false}"

echo "Create Keptn Project"
# create keptn project
keptn create project $KEPTN_PROJECT_NAME  --shipyard=./keptn/shipyard.yaml --git-user=$GIT_USER --git-token=$GIT_TOKEN --git-remote-url=http://$GIT_URL/$GIT_USER/$GIT_REPO.git

# configure Dynatrace service
keptn add-resource --project=$KEPTN_PROJECT_NAME --resource=./keptn/dynatrace/dynatrace.conf.yaml --resourceUri=dynatrace/dynatrace.conf.yaml
keptn configure monitoring dynatrace --project=$KEPTN_PROJECT_NAME

# add sli and slo config
#keptn add-resource --project=$KEPTN_PROJECT_NAME --stage=staging --service=simplenode --resource=./keptn/dynatrace/sli.yaml --resourceUri=dynatrace/sli.yaml
#keptn add-resource --project=$KEPTN_PROJECT_NAME --stage=staging --service=simplenode --resource=./keptn/slo.yaml --resourceUri=slo.yaml

echo "Create simplenode Service"
keptn create service simplenode --project=$KEPTN_PROJECT_NAME
# add helm chart for service
echo "Add simplenode charts"
keptn add-resource --project=$KEPTN_PROJECT_NAME --service=simplenode --resource=./simplenode.tgz --resourceUri=helm/simplenode.tgz --all-stages
# add jmx config
echo "Add JMeter test"
keptn add-resource --project=$KEPTN_PROJECT_NAME --stage=staging --service=simplenode --resource=./keptn/jmeter/load.jmx --resourceUri=jmeter/load.jmx
keptn add-resource --project=$KEPTN_PROJECT_NAME --stage=staging --service=simplenode --resource=./keptn/jmeter/jmeter.conf.yaml --resourceUri=jmeter/jmeter.conf.yaml
# deploy initial version
#echo "Deploy simplenode v1"
#keptn trigger delivery --project=$KEPTN_PROJECT_NAME --service=simplenode  --image=docker.io/robinwyss/simplenodeservice --tag=1.0.1

echo "Deploy sample petclinic app"
kubectl create namespace petclinic
kubectl apply -f demo/petclinic.yaml --namespace petclinic
#get keptn bridge username and password
KEPTN_BRIDGE_PW=$(kubectl -n keptn get secret bridge-credentials -o jsonpath="{.data.BASIC_AUTH_PASSWORD}" | base64 --decode)
KEPTN_BRIDGE_USER=$(kubectl -n keptn get secret bridge-credentials -o jsonpath="{.data.BASIC_AUTH_USERNAME}}" | base64 --decode)


cat << EOF
Installation Complet!

- Dynatrace Tenant: $DT_TENANT
- Keptn Bridge: $KEPTN_BRIDGE_URL
  - User: $KEPTN_BRIDGE_USER Password: $KEPTN_BRIDGE_PW
- Git: $GIT_URL
  - User: $GIT_USER Password: $GIT_PASSWORD
EOF


