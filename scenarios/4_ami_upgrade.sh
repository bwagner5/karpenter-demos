#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "${SCRIPTPATH}/../lib/utils.sh"

## AMI Upgrade Drift DEMO: 
## This demo shows a roll out of a new AMI via Drift
## Points:
##  - Rolls nodes with new AMI

## Clean-up previous demo resources
kubectl get nodepool --no-headers | tr -s " " | cut -d " " -f1 | xargs kubectl delete nodepool > /dev/null 2>&1 || :
kubectl get ec2nodeclass --no-headers | tr -s " " | cut -d " " -f1 | xargs kubectl delete ec2nodeclass > /dev/null 2>&1 || :
kubectl delete all -l demo > /dev/null 2>&1

cat << EOF > /tmp/node-pool-ami-upgrade.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-ami-upgrade
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5s
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-ami-upgrade
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64", "arm64"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
  labels:
    demo: demo-ami-upgrade
spec:
  role: KarpenterNodeRole-${CLUSTER_NAME}
  amiFamily: AL2
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${CLUSTER_NAME}
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${CLUSTER_NAME}
EOF

cmd "cat /tmp/node-pool-ami-upgrade.yaml"
cmd "kubectl apply -f /tmp/node-pool-ami-upgrade.yaml"

cat << EOF > /tmp/deployment-ami-upgrade.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-ami-upgrade
  labels:
    demo: demo-ami-upgrade
spec:
  selector:
    matchLabels:
      app: inflate-demo-ami-upgrade
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-ami-upgrade
        demo: demo-ami-upgrade
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-ami-upgrade
        resources:
          requests:
            cpu: "1"
            memory: 256M
      topologySpreadConstraints:
        - maxSkew: 3
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: inflate-demo-ami-upgrade
EOF

cmd "cat /tmp/deployment-ami-upgrade.yaml"
cmd "kubectl apply -f /tmp/deployment-ami-upgrade.yaml"
cmd "kubectl scale deployment inflate-demo-ami-upgrade --replicas=10"


## Retrieve different AMI IDs to "upgrade" to
## These are technically older, but the point is that they are different from the latest
k8sMinorVersion=$(kubectl version -o json | jq -r '.serverVersion.minor' | tr -d "+")
prevMinorVersion=$(( k8sMinorVersion - 1 ))
amd64PrevAMI=$(amictl get eks-al2 -c amd64 -k "1.${prevMinorVersion}" -o yaml | jq -r '.[0] .ImageId')
arm64PrevAMI=$(amictl get eks-al2 -c arm64 -k "1.${prevMinorVersion}" -o yaml | jq -r '.[0] .ImageId')

cat << EOF > /tmp/demo-ami-upgrade.yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
  labels:
    demo: demo-ami-upgrade
spec:
  amiSelectorTerms:
    - id: ${amd64PrevAMI}
    - id: ${arm64PrevAMI}
  role: KarpenterNodeRole-${CLUSTER_NAME}
  amiFamily: AL2
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${CLUSTER_NAME}
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${CLUSTER_NAME}
EOF

cmd "cat /tmp/demo-ami-upgrade.yaml"
cmd "kubectl apply -f /tmp/demo-ami-upgrade.yaml"
cmd "echo 'Waiting for nodes to be upgraded'"

cmd "kubectl scale deployment inflate-demo-ami-upgrade --replicas=0"
cmd "kubectl delete nodes -l 'karpenter.sh/nodepool'"
