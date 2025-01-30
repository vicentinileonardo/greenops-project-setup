# GreenOps Project Installation: Part 2 - MLOps stack

## Requirements

- Kubernetes cluster
- kubectl
- helm
- cert-manager already installed in the cluster (see [install_1.md](install_1.md))

## Install CrateDB Operator and CrateDB Cluster

Create the `cratedb` namespace:
```sh
kubectl create ns cratedb
```

Add the CrateDB Helm repository and install the CrateDB Operator:
```sh
helm repo add crate-operator https://crate.github.io/crate-operator
helm repo update
helm upgrade --install --atomic crate-operator crate-operator/crate-operator \
    --namespace=crate-operator \
    --create-namespace \
    --set resources.requests.memory=256Mi \
    --set resources.limits.memory=256Mi
```

Test if CrateDB CRDs are installed correctly:
```sh
kubectl get crds | grep crate
```

Verify that the CrateDB Operator pods are running:
```sh
kubectl get pods -n crate-operator
```

Create a `CrateDB` custom resource (make sure to configure the StorageClass according to your cluster):
```sh
export STORAGE_CLASS=azurefile-csi-premium
cat <<EOF | kubectl apply -f -
apiVersion: cloud.crate.io/v1
kind: CrateDB
metadata:
  name: cratedb-cluster
  namespace: cratedb
spec:
  cluster:
    imageRegistry: crate
    name: crate-dev
    version: 5.9.6
  nodes:
    data:
    - name: hot
      replicas: 2
      resources:
        limits:
          cpu: 0.20
          memory: 4Gi
        disk:
          count: 1
          size: 32GiB
          storageClass: $STORAGE_CLASS
        heapRatio: 0.25
EOF
```

Verify that the CrateDB cluster is running:
```sh
kubectl get pods -n cratedb
```

Create a secret with the CrateDB credentials for MLflow tracking server:
```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cratedb-credentials
  namespace: mlflow-tracking
type: Opaque
stringData:
  CRATEDB_USERNAME: system
  CRATEDB_PASSWORD: $(kubectl get secret -n cratedb user-system-cratedb-cluster -o json | jq -r '.data.password' | base64 -d)
EOF
```

### Testing CrateDB

Get CrateDB password for the `system` user:
```sh
kubectl get secret -n cratedb user-system-cratedb-cluster -o json | jq -r '.data.password' | base64 -d
```

Create a pod to test the CrateDB service (make sure to replace the access key and secret key with the ones obtained above):
```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: python-test-pod
  labels:
    app: python-test
spec:
  containers:
  - name: python-container
    image: python:3.10-slim  # Minimal Python image with pip included
    command: ["/bin/sh", "-c"]
    args:
    - |
      pip install crash && \
      sleep 36000  # Keep the pod alive
    resources:
      limits:
        memory: "256Mi"
        cpu: "500m"
  restartPolicy: Never
EOF
```

Access the pod:
```sh
kubectl exec -it python-test-pod -- /bin/sh
```

Test the connection to the CrateDB cluster:
```sh
crash --hosts http://system:<CRATEDB_PASSWORD>@crate-cratedb-cluster.cratedb.svc.cluster.local:4200/
```

Exit the pod:
```sh
exit
```

Delete the pod:
```sh
kubectl delete pod python-test-pod
```

## Install SeaweedFS

Create the namespace
```bash
kubectl create namespace seaweedfs
```

Create the `mlflow-tracking` namespace (needed for a secret created in this section):
```sh
kubectl create ns mlflow-tracking
```

Add the SeaweedFS Helm repository:
```sh
helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm
helm repo update
```

Create the secrets:
```sh
chmod +x seaweedfs/secret.sh && ./seaweedfs/secret.sh
```

Install the Helm chart:
```sh
helm install --values=seaweedfs/seaweedfs-values.yaml seaweedfs seaweedfs/seaweedfs --namespace=seaweedfs
```

Wait for the SeaweedFS pods to be ready:
```bash
# Wait for master
kubectl wait --for=condition=ready pods -l app.kubernetes.io/component=master -n seaweedfs --timeout=300s

# Wait for volume servers
kubectl wait --for=condition=ready pods -l app.kubernetes.io/component=volume -n seaweedfs --timeout=300s

# Wait for filer
kubectl wait --for=condition=ready pods -l app.kubernetes.io/component=filer -n seaweedfs --timeout=300s
```

### Testing SeaweedFS

Get credentials:
```sh
kubectl get secret s3-secret-deployment -n mlflow-tracking -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode

kubectl get secret s3-secret-deployment -n mlflow-tracking -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode
```

Create a pod to test the SeaweedFS S3 service (make sure to replace the access key and secret key with the ones obtained above):
```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: python-test-pod
  labels:
    app: python-test
spec:
  containers:
  - name: python-container
    image: python:3.10-slim  # Minimal Python image with pip included
    command: ["/bin/sh", "-c"]
    args:
    - |
      pip install awscli && \
      sleep 36000  # Keep the pod alive
    resources:
      limits:
        memory: "256Mi"
        cpu: "500m"
    env:
    - name: AWS_ACCESS_KEY_ID
      value: "<AWS_ACCESS_KEY_ID>"  # Replace with your access key
    - name: AWS_SECRET_ACCESS_KEY
      value: "<AWS_SECRET_ACCESS_KEY>"  # Replace with your secret key
  restartPolicy: Never
EOF
```

Access the pod:
```sh
kubectl exec -it python-test-pod -- /bin/sh
```

List the buckets:
```sh
aws --endpoint-url http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333 s3 ls 
```

The expected output is to see the `mlartifacts` bucket.
That bucket is automatically created by SeaweedFS (with current configuration).

Check the bucket contents:
```sh
aws --endpoint-url http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333 s3 ls s3://mlartifacts
```

Exit the pod:
```sh
exit
```

Delete the pod:
```sh
kubectl delete pod python-test-pod
```

## Install MLflow tracking server

Since we use CrateDB as the metadata store, we need to install the MLflow adapter for CrateDB.

Create the `mlflow-tracking` namespace:
```sh
kubectl create ns mlflow-tracking
```

Install MLflow tracking server (MLFlow adapter for CrateDB) with the following commands:
```sh
helm repo add lv https://leonardovicentini.com/helm-charts/charts
helm repo update
helm install mlflow-cratedb lv/mlflow-cratedb -n mlflow-tracking \
    --set mlflow.resources.requests.memory=250Mi \
    --set mlflow.resources.requests.cpu=0.20 
```

### Testing MLflow tracking server

Get the MLflow tracking server URL:
```sh
kubectl get svc mlflow-tracking -n mlflow-tracking -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Access the MLflow tracking server URL in your browser at `http://<MLFLOW_TRACKING_SERVER_IP>:5000`.

## Install KServe (Serverless mode)

```sh
export deploymentMode=Serverless
export ISTIO_VERSION=1.23.2
export KSERVE_VERSION=v0.14.1
export GATEWAY_API_VERSION=v1.2.1
export KNATIVE_OPERATOR_VERSION=v1.15.7
export KNATIVE_SERVING_VERSION=1.15.2

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml

helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update

helm install istio-base istio/base -n istio-system --wait --set defaultRevision=default --create-namespace --version ${ISTIO_VERSION}

helm install istiod istio/istiod -n istio-system --wait --version ${ISTIO_VERSION} \
   --set proxy.autoInject=disabled \
   --set-string pilot.podAnnotations."cluster-autoscaler\.kubernetes\.io/safe-to-evict"=true

helm install istio-ingressgateway istio/gateway -n istio-system --version ${ISTIO_VERSION} \
   --set-string podAnnotations."cluster-autoscaler\.kubernetes\.io/safe-to-evict"=true

# Wait for the istio ingressgateway pod to be created
sleep 10
# Wait for istio ingressgateway to be ready
kubectl wait --for=condition=Ready pod -l app=istio-ingressgateway -n istio-system --timeout=600s

helm install knative-operator --namespace knative-serving --create-namespace --wait \
  https://github.com/knative/operator/releases/download/knative-${KNATIVE_OPERATOR_VERSION}/knative-operator-${KNATIVE_OPERATOR_VERSION}.tgz

kubectl apply -f - <<EOF
apiVersion: operator.knative.dev/v1beta1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: knative-serving
spec:
  version: "${KNATIVE_SERVING_VERSION}"
  config:
    domain:
      # Patch the external domain as the default domain svc.cluster.local is not exposed on ingress (from knative 1.8)
      example.com: ""
EOF

# Install KServe
helm install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd --version ${KSERVE_VERSION} --namespace kserve --create-namespace --wait
helm install kserve oci://ghcr.io/kserve/charts/kserve --version ${KSERVE_VERSION} --namespace kserve --create-namespace --wait \
   --set-string kserve.controller.deploymentMode="${deploymentMode}" --set kserve.modelmesh.enabled=false
```


## (DUMMY) Apply KServe InferenceService (Working example)

This is a dummy example to test KServe.

Create the `model-inference` namespace:
```sh
kubectl create ns model-inference
```

Apply the KServe InferenceService:
```sh
cat <<EOF | kubectl apply -f -
apiVersion: "serving.kserve.io/v1beta1"
kind: "InferenceService"
metadata:
  name: "mlflow-wine-classifier"
  namespace: "model-inference"
spec:
  predictor:
    containers:
      - name: "mlflow-wine-classifier"
        image: "leovice/mlflow-wine-classifier"
        ports:
          - containerPort: 8080
            protocol: TCP
        env:
          - name: PROTOCOL
            value: "v2"
EOF
```

Checking the status of the InferenceService:
```sh
kubectl get inferenceservice mlflow-wine-classifier -n model-inference
```


### Testing the InferenceService

#### Spinning up a test client
```bash
kubectl run --rm -it --image=alpine/curl:latest test-client -- /bin/sh
```

#### Testing health endpoints
```bash
# Check if the server is ready
curl -v http://mlflow-wine-classifier.model-inference.svc.cluster.local/v2/health/ready
# Response
# 200 OK

# Check if the server is live
curl -v http://mlflow-wine-classifier.model-inference.svc.cluster.local/v2/health/live
# Response
# 200 OK

# GET server metadata
curl -v http://mlflow-wine-classifier.model-inference.svc.cluster.local/v2
# Response
# {"name":"mlserver","version":"1.3.5","extensions":[]}
```

#### Getting available models
```bash
curl -v http://mlflow-wine-classifier.model-inference.svc.cluster.local/v2/repository/index \
     -H "Content-Type: application/json" \
     -d '{}' 
# Response
# [{"name":"mlflow-model","version":"dce3966053da44658dc78889d02ac9d8","state":"READY","reason":""}]
```

#### Getting model metadata
```bash
curl -v http://mlflow-wine-classifier.model-inference.svc.cluster.local/v2/models/mlflow-model
# Response
# {"name":"mlflow-model","versions":[],"platform":"","inputs":[{"name":"input-0","datatype":"FP64","shape":[-1,13],"parameters":{"content_type":"np"}}],"outputs":[{"name":"output-0","datatype":"FP64","shape":[-1],"parameters":{"content_type":"np"}}],"parameters":{"content_type":"np"}}
```

#### Checking if the model is ready
```bash
curl -v http://mlflow-wine-classifier.model-inference.svc.cluster.local/v2/models/mlflow-model/ready
# Response
# 200 OK
```

#### Testing the infer endpoint
```bash
curl -v http://mlflow-wine-classifier.model-inference.svc.cluster.local/v2/models/mlflow-model/infer \
     -H "Content-Type: application/json" \
     -d '{
    "inputs": [
        {
            "name": "input",
            "shape": [1, 13],
            "datatype": "FP64",
            "data": [[14.23, 1.71, 2.43, 15.6, 127.0, 2.8, 3.06, 0.28, 2.29, 5.64, 1.04, 3.92, 1065.0]]
        }
    ]
}' 

# Response
# {"model_name":"mlflow-model","model_version":"dce3966053da44658dc78889d02ac9d8","id":"************************************","parameters":{"content_type":"np"},"outputs":[{"name":"output-1","shape":[1,1],"datatype":"FP64","parameters":{"content_type":"np"},"data":[0.44111927902918846]}]}
```






## Apply KServe InferenceService (TorchServe - PyTorch) (actual production model)

TODO: understand how to set limits and requests for the inference service

Create the `model-inference` namespace:
```sh
kubectl create ns model-inference
```

Apply the KServe InferenceService:
```sh
cat <<EOF | kubectl apply -f -
apiVersion: "serving.kserve.io/v1beta1"
kind: "InferenceService"
metadata:
  name: "forecaster1"
spec:
  predictor:
    model:
      args: ["--enable_docs_url=True"]
      modelFormat:
        name: pytorch
      protocolVersion: v2  
      storageUri: s3://mlartifacts/forecaster1
EOF
```

Checking the status of the InferenceService:
```sh
kubectl get inferenceservice forecaster1 -n model-inference
```
