#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "${SCRIPTPATH}/../lib/utils.sh"

## Consolidation DEMO: 
## This demo shows how consolidation can help to make the cluster more cost efficient
## Points:
##  - Resizes node based on cheaper instance types
##    - Start with OD amd64
##    - Add arm64
##    - Add Spot

## Clean-up previous demo resources
kubectl delete all -l demo > /dev/null 2>&1
kubectl delete nodepool default > /dev/null 2>&1 || :
kubectl delete ec2nodeclass default > /dev/null 2>&1 || :

cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-consolidation
spec:
  disruption:
    consolidationPolicy: WhenUnderUtilized
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-consolidation
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
    demo: demo-consolidation
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

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-consolidation
  labels:
    demo: demo-consolidation
spec:
  selector:
    matchLabels:
      app: inflate-demo-consolidation
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-consolidation
        demo: demo-consolidation
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-consolidation
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
              app: inflate-demo-consolidation
EOF

cmd "kubectl scale deployment inflate-demo-consolidation --replicas=300"


cat << EOF > /tmp/demo-consolidation-arm64.yaml
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-consolidation
spec:
  disruption:
    consolidationPolicy: WhenUnderUtilized
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-consolidation
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
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
EOF

cmd "cat /tmp/demo-consolidation-arm64.yaml"
cmd "kubectl apply -f /tmp/demo-consolidation-arm64.yaml"

cat << EOF > /tmp/demo-consolidation-spot.yaml
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-consolidation
spec:
  disruption:
    consolidationPolicy: WhenUnderUtilized
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-consolidation
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
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
EOF

cmd "cat /tmp/demo-consolidation-spot.yaml"
cmd "kubectl apply -f /tmp/demo-consolidation-spot.yaml"

cmd "kubectl scale deployment inflate-demo-consolidation --replicas=0"
cmd "kubectl delete nodes -l 'karpenter.sh/provisioner-name'"
