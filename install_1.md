# GreenOps Project Installation: Part 1 - Cloud Providers' Operators

## Requirements

- Kubernetes cluster
- kubectl
- helm
- Azure Subscription for Azure Operator (optional)
- gcloud CLI for GCP Operator (optional)

## Create required namespace

```sh
kubectl create ns greenops
```

## Install cert-manager

cert-manger is needed by Azure Service Operator and KServe (see [install_2.md](install_2.md)).

Install cert-manager with the following command:
```sh
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
```

Verify that the cert-manager pods are running:
```sh
kubectl get pods -n cert-manager
```

## Install Azure Operator

```sh
helm repo add aso2 https://raw.githubusercontent.com/Azure/azure-service-operator/main/v2/charts
helm repo update
helm upgrade --install aso2 aso2/azure-service-operator \
    --create-namespace \
    --namespace=azureserviceoperator-system \
    --set crdPattern='resources.azure.com/*;compute.azure.com/*;network.azure.com/*'
```

Test if ASO2 CRDs are installed correctly:
```sh
kubectl get virtualnetworks.network.azure.com --all-namespaces
kubectl get virtualnetworkssubnets.network.azure.com --all-namespaces
kubectl get networkinterfaces.network.azure.com --all-namespaces
kubectl get virtualmachines.compute.azure.com --all-namespaces
```

Create `aso-credential` secret that contains the Azure credentials (make sure to replace the <PLACEHOLDER> with the actual values).
The secret must be named `aso-credential` and be created in the namespace you’d like to create ASO resources in (in this case, `greenops`):
```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
 name: aso-credential
 namespace: greenops
stringData:
 AZURE_SUBSCRIPTION_ID: <PLACEHOLDER>
 AZURE_TENANT_ID: <PLACEHOLDER>
 AZURE_CLIENT_ID: <PLACEHOLDER>
 AZURE_CLIENT_SECRET: <PLACEHOLDER>
EOF
```

Create the `greenops-vm-secret` secret that contains the password for the VMs (make sure to replace the <PLACEHOLDER> with the actual value):
```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
 name: greenops-vm-secret
 namespace: greenops
stringData:
 password: <PLACEHOLDER>
EOF
```

## Install GCP Operator

Source: https://cloud.google.com/config-connector/docs/how-to/install-other-kubernetes

Create the cnrm-system namespace:
```sh
kubectl create namespace cnrm-system
```

Import the key's credentials as a Secret (important: the file must be named key.json to create a valid Secret):
```sh
kubectl create secret generic sa-secret \
    --from-file key.json \
    --namespace cnrm-system
```

Remove the credentials from your system:
```sh
rm key.json
```

Download the latest Config Connector Operator tar file:
```sh
gcloud storage cp gs://configconnector-operator/latest/release-bundle.tar.gz release-bundle.tar.gz
```

Extract the tar file:
```sh
tar zxvf release-bundle.tar.gz
```

Install the Config Connector Operator on your cluster:
```sh
kubectl apply -f operator-system/configconnector-operator.yaml
```

Apply the ConfigConnector custom resource:
```sh
export GCP_SECRET_NAME=sa-secret
cat <<EOF | kubectl apply -f -
apiVersion: core.cnrm.cloud.google.com/v1beta1
kind: ConfigConnector
metadata:
  # the name is restricted to ensure that there is only ConfigConnector
  # instance installed in your cluster
  name: configconnector.core.cnrm.cloud.google.com
spec:
  mode: cluster
  credentialSecretName: $GCP_SECRET_NAME
  stateIntoSpec: Absent
EOF
```

Verify that the Config Connector pods are running:
```sh
kubectl get pods -n cnrm-system
```

Solve OOM issues, if any:
(https://github.com/GoogleCloudPlatform/k8s-config-connector/issues/240#issuecomment-764932872)

```sh
kubectl scale statefulset configconnector-operator --replicas=0 -n configconnector-operator-system

kubectl -n cnrm-system patch deployment cnrm-webhook-manager --patch '{"spec":{"template":{"spec":{"containers":[{"name":"webhook","env":[{"name":"GOMEMLIMIT","value":"450MiB"}],"resources":{"limits":{"memory":"512Mi","cpu":"500m"},"requests":{"memory":"512Mi","cpu":"500m"}}}]}}}}'

kubectl -n cnrm-system patch deployment cnrm-resource-stats-recorder --patch '{"spec":{"template":{"spec":{"containers":[{"name":"recorder","resources":{"limits":{"memory":"512Mi","cpu":"500m"},"requests":{"memory":"512Mi","cpu":"500m"}}}]}}}}'

# keep configconnector-operator (not config connector itself) at 0 replicas
```


## Install AWS Operator

Put the AWS credentials in a file called `credentials`.

```sh
export RELEASE_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/${SERVICE}-controller/releases/latest | jq -r '.tag_name | ltrimstr("v")')

kubectl create secret generic aws-creds \
  --from-file=credentials-file=./credentials \
  --namespace=ack-system \
  --type=Opaque

# testing secret content
kubectl get secret aws-creds --namespace=ack-system -o jsonpath='{.data.credentials-file}' | base64 --decode
```

Install the AWS Operator (make sure to replace the <PLACEHOLDER> with the actual values):
```sh
helm install -n ack-system ack-ec2-controller oci://public.ecr.aws/aws-controllers-k8s/ec2-chart \
--version=$RELEASE_VERSION \
--set=aws.region=us-east-1 \
--set=aws.credentials.secretName=aws-creds \
--set=aws.credentials.secretKey=credentials-file \
--set=aws.credentials.profile=<PLACEHOLDER>

# testing that pod is running correctly
kubectl get all -n ack-system
```
