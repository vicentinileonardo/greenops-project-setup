# GreenOps Project Installation: Part 4 - VmTemplate and GreenOps Scheduler


## Install VmTemplate Composition Definition

```sh
kubectl apply -f https://raw.githubusercontent.com/vicentinileonardo/vm-template/refs/heads/main/compositiondefinition.yaml

DATE=$(date +"%Y-%m-%dT%H:%M:%SZ")
curl -sL "https://raw.githubusercontent.com/vicentinileonardo/vm-template/main/customform.yaml" | sed "s/{{DATE}}/$DATE/" | kubectl apply -f -

kubectl apply -f https://raw.githubusercontent.com/vicentinileonardo/vm-template/refs/heads/main/patch.yaml
```


## Install GreenOps Scheduler

## GreenOps CronJob
