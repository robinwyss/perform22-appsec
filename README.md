# perform21-appsec

This repository contains the scripts and resources required to setup the lab environment for the perform HOT Session for App Sec.

## Prerequisits
- Kubernetes Cluster
- Dynatrace Environment
- Dynatrace PaaS Token
- Dynatrace API Token
  - Required scope: `entities.read`, `entities.write`, `logs.read`, `metrics.read`, `metrics.write`, `DataExport`, `LogExport`, `ReadConfig`, `WriteConfig`, `securityProblems.read`
  - Example curl: 
    - `curl -X POST "ENVIRONMENT/api/v2/apiTokens" -H "accept: application/json; charset=utf-8" -H "Content-Type: application/json; charset=utf-8" -d "{\"name\":\"keptn\",\"scopes\":[\"entities.read\",\"entities.write\",\"logs.read\",\"metrics.read\",\"metrics.write\",\"DataExport\",\"LogExport\",\"ReadConfig\",\"WriteConfig\",\"securityProblems.read\"]}" -H "Authorization: Api-Token XXXXXXXX"`
  - See https://keptn.sh/docs/0.8.x/monitoring/dynatrace/install/

## Usage
- Clone this repository
- make the script executable `chmod +x setup-env.sh`
- Set DT_TENANT, DT_API_TOKEN, DT_PAAS_TOKEN
  - `export DT_TENANT=..`
  - `export DT_API_TOKEN=..`
  - `export DT_PAAS_TOKEN=..`
- Run script `./setup-env.sh`
