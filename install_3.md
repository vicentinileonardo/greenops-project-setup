# GreenOps Project Installation: Part 3 - OPA and K8s Mutating Webhook




## Install OPA



## Set K8s mutating webhook configuration

Generate the mutating webhook configuration file:

```bash
cat > webhook-configuration.yaml <<EOF
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

Apply the mutating webhook configuration:
```bash
kubectl apply -f webhook-configuration.yaml
```

You can follow the OPA logs to see the webhook requests being issued by the Kubernetes API server:

```bash
# ctrl-c to exit
kubectl logs -l app=opa -c opa -f
```








