# GreenOps Project Installation: Part 4 - GreenOps Scheduler and Forecasts update CronJob

## Install GreenOps Scheduler

Create namespace:
```sh
kubectl create namespace greenops-scheduler-system
```

Set the following variables:
```sh
SERVICE_NAME=crate-cratedb-cluster
NAMESPACE=cratedb
PORT=4200
SERVICE_DNS="${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local"
CRATEDB_HOST="${SERVICE_DNS}:${PORT}"
```

Create a Secret with the CrateDB database credentials:
```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: greenops-scheduler-system
type: Opaque
stringData:
  CRATEDB_HOST: "${CRATEDB_HOST}"
  CRATEDB_USERNAME: system
  CRATEDB_PASSWORD: $(kubectl get secret -n cratedb user-system-cratedb-cluster -o json | jq -r '.data.password' | base64 -d)
EOF
```

Apply the GreenOps Scheduler Helm chart:
```sh
helm repo add lv https://leonardovicentini.com/helm-charts/charts
helm repo update
helm install greenops-scheduler lv/greenops-scheduler -n greenops-scheduler-system
```


### Spinning up a test client

```sh
kubectl run --rm -it --image=alpine/curl:latest test-client -- /bin/sh
```

Test endpoints:
```sh
curl -v http://greenops-scheduler.greenops-scheduler-system.svc.cluster.local/health

# Expected output:
#{"database":"connected","status":"healthy"}


curl -X POST -H "Content-Type: application/json" \
-d '{
  "number_of_jobs" : 1,
  "eligible_regions": ["IT", "FR", "FI"],
  "deadline": "2025-06-09T10:00:00",
  "duration": 6,
  "cpu": 4,
  "memory": 8,
  "req_timeout": 180
}' http://greenops-scheduler.greenops-scheduler-system.svc.cluster.local/scheduling

```

### External access (development purpose only)

```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: greenops-scheduler-external
  namespace: greenops-scheduler-system
spec:
  type: LoadBalancer
  selector:
    app: greenops-scheduler  # Match the deployment's label
  ports:
    - port: 80
      targetPort: 8000  # Match your container's port
EOF
```

## Forecasts updater CronJob (K8s Deployment)

Set the following variables:
```sh
REGISTRY="docker.io/leovice"
IMAGE="forecasts-updater"
VERSION="1.0.0"

SERVICE_NAME=crate-cratedb-cluster
NAMESPACE=cratedb
PORT=4200
SERVICE_DNS="${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local"
CRATEDB_HOST="${SERVICE_DNS}:${PORT}"
```

Create a Secret with the CrateDB database credentials:
```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: greenops
type: Opaque
stringData:
  CRATEDB_HOST: "${CRATEDB_HOST}"
  CRATEDB_USERNAME: system
  CRATEDB_PASSWORD: $(kubectl get secret -n cratedb user-system-cratedb-cluster -o json | jq -r '.data.password' | base64 -d)
EOF
```

Create the Forecasts updater deployment
```sh

```
