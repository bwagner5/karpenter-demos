#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "${SCRIPTPATH}/../lib/utils.sh"

## Weighted DEMO: 
## This demo shows how you can setup multiple NodePools with weights and limits to handle your Savings Plans or Reserved Instances
## Points:
##  - Create 2 NodePools
##  - Adjust the requirements of the first NodePool with an RI or Savings Plan you have (m5.large)
##  - Adjust the Limit of the first NodePool to only allow the RI or Savings Plan terms
##  - Set the next NodePool as a general purpose overflow after the Savings Plans/RIs have been used

## Clean-up previous demo resources
kubectl get nodepool --no-headers | tr -s " " | cut -d " " -f1 | xargs kubectl delete nodepool > /dev/null 2>&1 || :
kubectl get ec2nodeclass --no-headers | tr -s " " | cut -d " " -f1 | xargs kubectl delete ec2nodeclass > /dev/null 2>&1 || :
kubectl delete all -l demo > /dev/null 2>&1

cat << EOF > /tmp/node-pool-default.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-weights
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 2s
  template:
    metadata:
      labels:
        demo: demo-weights
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
    demo: demo-weights
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

cat << EOF > /tmp/node-pool-sp.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: sp
  labels:
    demo: demo-weights
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 2s
  weight: 50
  limits:
    cpu: 32
  template:
    metadata:
      labels:
        demo: demo-weights
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["m5.xlarge"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
EOF

cmd "cat /tmp/node-pool-default.yaml"
cmd "cat /tmp/node-pool-sp.yaml"
cmd "kubectl apply -f /tmp/node-pool-default.yaml"
cmd "kubectl apply -f /tmp/node-pool-sp.yaml"

cat << EOF > /tmp/demo-inflate-demo-weights.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-weights-1
  labels:
    demo: demo-weights
spec:
  selector:
    matchLabels:
      app: inflate-demo-weights-1
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-weights-1
        demo: demo-weights
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-weights
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
              app: inflate-demo-weights-1
EOF

cmd "cat /tmp/demo-inflate-demo-weights.yaml"
cmd "kubectl apply -f /tmp/demo-inflate-demo-weights.yaml"
cmd "kubectl scale deployment inflate-demo-weights-1 --replicas=100"

cmd "kubectl get nodepool sp -o yaml | less"

cmd "kubectl scale deployment inflate-demo-weights-1 --replicas=0"


cmd "kubectl delete nodes -l 'karpenter.sh/nodepool'"
