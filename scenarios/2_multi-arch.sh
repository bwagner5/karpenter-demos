#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "${SCRIPTPATH}/../lib/utils.sh"

## MULTI-ARCH DEMO: 
## This demo shows a multi-arch cluster setup 
## Points:
##  - Provisioner can span multiple cpu architectures
##  - Pods can select a specific CPU architecture

## Clean-up previous demo resources
kubectl delete nodepool default > /dev/null 2>&1 || :
kubectl delete ec2nodeclass default > /dev/null 2>&1 || :
kubectl delete all -l demo > /dev/null 2>&1

cat << EOF > /tmp/node-pool-multi-arch.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-multi-arch
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5s
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-multi-arch
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
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
  labels:
    demo: demo-multi-arch
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

cmd "cat /tmp/node-pool-multi-arch.yaml"
cmd "kubectl apply -f /tmp/node-pool-multi-arch.yaml"

## No Arch selector (use either one)
cat << EOF > /tmp/deployment-multi-arch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-multi-arch
  labels:
    demo: demo-multi-arch
spec:
  selector:
    matchLabels:
      app: inflate-demo-multi-arch
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-multi-arch
        demo: demo-multi-arch
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-multi-arch
        resources:
          requests:
            cpu: "1"
            memory: 256M
      topologySpreadConstraints:
      - labelSelector:
          matchLabels:
            app: inflate-demo-multi-arch
        maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
EOF

cmd "cat /tmp/deployment-multi-arch.yaml"
cmd "kubectl apply -f /tmp/deployment-multi-arch.yaml"
cmd "kubectl scale deployment inflate-demo-multi-arch --replicas=10"
cmd "kubectl scale deployment inflate-demo-multi-arch --replicas=0"

## Select AMD64
cat << EOF > /tmp/deployment-multi-arch-amd64.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-multi-arch-amd64
  labels:
    demo: demo-multi-arch
spec:
  selector:
    matchLabels:
      app: inflate-demo-multi-arch-amd64
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-multi-arch-amd64
        demo: demo-multi-arch
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-multi-arch-amd64
        resources:
          requests:
            cpu: "1"
            memory: 256M
      nodeSelector:
        kubernetes.io/arch: amd64
EOF

cmd "cat /tmp/deployment-multi-arch-amd64.yaml"
cmd "kubectl apply -f /tmp/deployment-multi-arch-amd64.yaml"
cmd "kubectl scale deployment inflate-demo-multi-arch-amd64 --replicas=10"
cmd "kubectl scale deployment inflate-demo-multi-arch-amd64 --replicas=0"

## Select ARM64
cat << EOF > /tmp/deployment-multi-arch-arm64.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-multi-arch-arm64
  labels:
    demo: demo-multi-arch
spec:
  selector:
    matchLabels:
      app: inflate-demo-multi-arch-arm64
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-multi-arch-arm64
        demo: demo-multi-arch
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-multi-arch-arm64
        resources:
          requests:
            cpu: "1"
            memory: 256M
      nodeSelector:
        kubernetes.io/arch: arm64
EOF

cmd "cat /tmp/deployment-multi-arch-arm64.yaml"
cmd "kubectl apply -f /tmp/deployment-multi-arch-arm64.yaml"
cmd "kubectl scale deployment inflate-demo-multi-arch-arm64 --replicas=10"
cmd "kubectl scale deployment inflate-demo-multi-arch-arm64 --replicas=0"

## Prefer ARM64 but fallback to AMD64
cat << EOF > /tmp/deployment-multi-arch-prefer.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-multi-arch-prefer-arm64
  labels:
    demo: demo-multi-arch
spec:
  selector:
    matchLabels:
      app: inflate-demo-multi-arch-prefer-arm64
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-multi-arch-prefer-arm64
        demo: demo-multi-arch
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-multi-arch-prefer-arm64
        resources:
          requests:
            cpu: "1"
            memory: 256M
      topologySpreadConstraints:
      - labelSelector:
          matchLabels:
            app: inflate-demo-multi-arch-prefer-arm64
        maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            preference:
              matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values:
                - amd64
          - weight: 50
            preference:
              matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values:
                - arm64
EOF

cmd "cat /tmp/deployment-multi-arch-prefer.yaml"
cmd "kubectl apply -f /tmp/deployment-multi-arch-prefer.yaml"
cmd "kubectl scale deployment inflate-demo-multi-arch-prefer-arm64 --replicas=10"
cmd "kubectl scale deployment inflate-demo-multi-arch-prefer-arm64 --replicas=0"


cmd "kubectl delete nodes -l 'karpenter.sh/nodepool'"