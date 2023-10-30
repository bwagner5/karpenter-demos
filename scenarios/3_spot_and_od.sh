#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "${SCRIPTPATH}/../lib/utils.sh"

## Spot and OD DEMO: 
## This demo shows a single provisioner that support On-Demand and Spot
## Points:
##  - Similar to CPU architecture
##  - Spot interruptions are handled by Karpenter

## Clean-up previous demo resources
kubectl delete nodepool default > /dev/null 2>&1 || :
kubectl delete ec2nodeclass default > /dev/null 2>&1 || :
kubectl delete all -l demo > /dev/null 2>&1

cat << EOF > /tmp/node-pool-default-spot-and-od.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-spot-and-od
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5s
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-spot-and-od
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
    demo: demo-spot-and-od
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

cmd "cat /tmp/node-pool-default-spot-and-od.yaml"
cmd "kubectl apply -f /tmp/node-pool-default-spot-and-od.yaml"

## No capacity-type selector, so it uses Spot by default
cat << EOF > /tmp/deployment-default-spot-and-od.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-spot-and-od
  labels:
    demo: demo-spot-and-od
spec:
  selector:
    matchLabels:
      app: inflate-demo-spot-and-od
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-spot-and-od
        demo: demo-spot-and-od
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-spot-and-od
        resources:
          requests:
            cpu: "1"
            memory: 256M
      topologySpreadConstraints:
      - labelSelector:
          matchLabels:
            app: inflate-demo-spot-and-od
        maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
EOF

cmd "cat /tmp/deployment-default-spot-and-od.yaml"
cmd "kubectl apply -f /tmp/deployment-default-spot-and-od.yaml"
cmd "kubectl scale deployment inflate-demo-spot-and-od --replicas=10"
cmd "kubectl scale deployment inflate-demo-spot-and-od --replicas=0"

## Selects Spot capacity-type
cat << EOF > /tmp/node-pool-default-spot-and-od-spot.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-spot-and-od-spot
  labels:
    demo: demo-spot-and-od
spec:
  selector:
    matchLabels:
      app: inflate-demo-spot-and-od-spot
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-spot-and-od-spot
        demo: demo-spot-and-od
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-spot-and-od-spot
        resources:
          requests:
            cpu: "1"
            memory: 256M
      nodeSelector:
        karpenter.sh/capacity-type: spot
      topologySpreadConstraints:
      - labelSelector:
          matchLabels:
            app: inflate-demo-spot-and-od-spot
        maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
EOF

cmd "cat /tmp/deployment-default-spot-and-od-spot.yaml"
cmd "kubectl apply -f /tmp/deployment-default-spot-and-od-spot.yaml"
cmd "kubectl scale deployment inflate-demo-spot-and-od-spot --replicas=10"
cmd "kubectl scale deployment inflate-demo-spot-and-od-spot --replicas=0"

## Select OD
cat << EOF > /tmp/node-pool-default-spot-and-od-od.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-spot-and-od-od
  labels:
    demo: demo-spot-and-od
spec:
  selector:
    matchLabels:
      app: inflate-demo-spot-and-od-od
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-spot-and-od-od
        demo: demo-spot-and-od
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-spot-and-od-od
        resources:
          requests:
            cpu: "1"
            memory: 256M
      nodeSelector:
        karpenter.sh/capacity-type: on-demand
      topologySpreadConstraints:
      - labelSelector:
          matchLabels:
            app: inflate-demo-spot-and-od-od
        maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
EOF

cmd "cat /tmp/deployment-default-spot-and-od-od.yaml"
cmd "kubectl apply -f /tmp/deployment-default-spot-and-od-od.yaml"
cmd "kubectl scale deployment inflate-demo-spot-and-od-od --replicas=10"
cmd "kubectl scale deployment inflate-demo-spot-and-od-od --replicas=0"

## Spread across Spot and OD
cat << EOF > /tmp/node-pool-default-spot-and-od-spread.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-spot-and-od-spread
  labels:
    demo: demo-spot-and-od
spec:
  selector:
    matchLabels:
      app: inflate-demo-spot-and-od-spread
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-spot-and-od-spread
        demo: demo-spot-and-od
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-spot-and-od-spread
        resources:
          requests:
            cpu: "1"
            memory: 256M
      topologySpreadConstraints:
        - maxSkew: 3
          topologyKey: karpenter.sh/capacity-type
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: inflate-demo-spot-and-od-spread
        - labelSelector:
            matchLabels:
              app: inflate-demo-spot-and-od-spread
          maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
EOF

cmd "cat /tmp/deployment-default-spot-and-od-spread.yaml"
cmd "kubectl apply -f /tmp/deployment-default-spot-and-od-spread.yaml"
cmd "kubectl scale deployment inflate-demo-spot-and-od-spread --replicas=10"
cmd "kubectl scale deployment inflate-demo-spot-and-od-spread --replicas=0"

cmd "kubectl delete nodes -l 'karpenter.sh/nodepool'"
