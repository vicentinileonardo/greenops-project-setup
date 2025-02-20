# GreenOps Project Installation: Part 3 - VmTemplate Composition Definition, OPA and K8s Mutating Webhook

## Requirements

- At least 1 OPA policy bundle available somewhere, pointed by the OPA server (e.g. https://github.com/vicentinileonardo/opa-bundle-scheduling)

## Install VmTemplate Composition Definition

```sh
kubectl apply -f https://raw.githubusercontent.com/vicentinileonardo/vm-template/refs/heads/main/compositiondefinition.yaml

DATE=$(date +"%Y-%m-%dT%H:%M:%SZ")
curl -sL "https://raw.githubusercontent.com/vicentinileonardo/vm-template/main/customform.yaml" | sed "s/{{DATE}}/$DATE/" | kubectl apply -f -

kubectl apply -f https://raw.githubusercontent.com/vicentinileonardo/vm-template/refs/heads/main/patch.yaml
```

## Install OPA

Source: https://github.com/vicentinileonardo/opa-chart

```sh
cd opa
```

Create a namespace for OPA:
```sh
kubectl create namespace opa
```

Label `kube-system` and `opa` namespaces so that OPA does not control the resources in those namespaces:
```bash
kubectl label ns kube-system openpolicyagent.org/webhook=ignore
kubectl label ns opa openpolicyagent.org/webhook=ignore
```

Communication between Kubernetes and OPA must be secured using TLS. 
To configure TLS, use `openssl` to create a certificate authority (CA) and certificate/key pair for OPA:

```sh
mkdir certs
cd certs
```

```sh
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -sha256 -key ca.key -days 100000 -out ca.crt -subj "/CN=admission_ca"
```

Generate the TLS key and certificate for OPA:
```sh
cat >server.conf <<EOF
[ req ]
prompt = no
req_extensions = v3_ext
distinguished_name = dn

[ dn ]
CN = opa.opa.svc

[ v3_ext ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, serverAuth
subjectAltName = DNS:opa.opa.svc,DNS:opa.opa.svc.cluster,DNS:opa.opa.svc.cluster.local
EOF
```

```sh
openssl genrsa -out server.key 2048
openssl req -new -key server.key -sha256 -out server.csr -extensions v3_ext -config server.conf
openssl x509 -req -in server.csr -sha256 -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 100000 -extensions v3_ext -extfile server.conf
```

Create a Secret to store the TLS credentials for OPA:
```sh
kubectl create secret tls opa-server --cert=server.crt --key=server.key --namespace opa
```

Get back to the root directory:
```sh
cd ..; cd ..
```

### Chart installation

Install the chart:
```sh
helm repo add lv https://leonardovicentini.com/helm-charts/charts
helm repo update
helm install opa lv/opa -n opa \
--set opa.configMaps.envConfig.data.SCHEDULER_URL="http://greenops-scheduler.greenops-scheduler-system.svc.cluster.local/scheduling"
```

## Set K8s mutating webhook configuration

Generate and apply the mutating webhook configuration file:

```bash
cat <<EOF | kubectl apply -f -
kind: MutatingWebhookConfiguration
apiVersion: admissionregistration.k8s.io/v1
metadata:
  name: opa-mutating-webhook
webhooks:
  - name: mutating-webhook.openpolicyagent.org
    namespaceSelector:
      matchExpressions:
      - key: openpolicyagent.org/webhook
        operator: NotIn
        values:
        - ignore
    rules:
      - operations: ["CREATE", "UPDATE"]
        apiGroups: ["composition.krateo.io"]  # Specify the correct API group
        apiVersions: ["v1-2-0"]  # Specify the correct version
        resources: ["vmtemplates"]  # Specify the correct resource
    clientConfig:
      caBundle: $(cat ./opa/certs/ca.crt | base64 | tr -d '\n')
      service:
        namespace: opa
        name: opa
    admissionReviewVersions: ["v1"]
    sideEffects: None
EOF
```

You can follow the OPA logs to see the webhook requests being issued by the Kubernetes API server:

```bash
# ctrl-c to exit
kubectl logs -l app=opa -n opa -c opa -f
```
