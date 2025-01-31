# GreenOps Project Installation: Part 4 - GreenOps Scheduler and Forecasts update CronJob

## Install GreenOps Scheduler

NOT READY YET

## Forecasts updater CronJob

Set the following variables:
```sh
REGISTRY="docker.io/leovice"
IMAGE="forecasts-updater"
VERSION="1.0.0"

SERVICE_NAME=crate-cratedb-cluster
NAMESPACE=cratedb
PORT=4200
DATABASE=default
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
  DATABASE: ${DATABASE}
  CRATEDB_USERNAME: system
  CRATEDB_PASSWORD: $(kubectl get secret -n cratedb user-system-cratedb-cluster -o json | jq -r '.data.password' | base64 -d)
EOF
```

Create the Forecasts updater CronJob:
```sh
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: forecasts-updater
  namespace: greenops
spec:
  schedule: "0 * * * *"  # Runs every hour
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 3
      template:
        spec:
          serviceAccountName: default
          restartPolicy: OnFailure
          containers:
          - name: forecasts-updater
            image: ${REGISTRY}/${IMAGE}:${VERSION}
            imagePullPolicy: IfNotPresent
                        
            # Resource constraints
            resources:
              requests:
                memory: "256Mi"
                cpu: "250m"
              limits:
                memory: "512Mi"
                cpu: "500m"
            
             envFrom:
             - secretRef:
                 name: db-credentials           
EOF
```
