#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "${SCRIPTPATH}/../lib/utils.sh"
## TODO!
## STANDARD DEMO:
## This demo shows a simple provisioner setup without many features.
## Points:
##  - Opinionated defaults (CMR > gen 2, EKS Optimized AMI, No Consolidation)

## Clean-up previous demo resources
kubectl delete nodepool default > /dev/null 2>&1 || :
kubectl delete ec2nodeclass default > /dev/null 2>&1 || :
kubectl delete all -l demo > /dev/null 2>&1 || :

cat << EOF > /tmp/node-pool-standard.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-standard
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5s
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-standard
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
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
    demo: demo-standard
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

cmd "cat /tmp/node-pool-standard.yaml"
cmd "kubectl apply -f /tmp/node-pool-standard.yaml"

cat << EOF > /tmp/deployment-standard.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-standard
  labels:
    demo: demo-standard
spec:
  selector:
    matchLabels:
      app: inflate-demo-standard
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-standard
        demo: demo-standard
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-standard
        resources:
          requests:
            cpu: "1"
            memory: 256M
      topologySpreadConstraints:
      - labelSelector:
          matchLabels:
            app: inflate-demo-standard
        maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
EOF

cmd "cat /tmp/deployment-standard.yaml"
cmd "kubectl apply -f /tmp/deployment-standard.yaml"

cmd "kubectl scale deployment inflate-demo-standard --replicas=10"

cmd "kubectl scale deployment inflate-demo-standard --replicas=0"

