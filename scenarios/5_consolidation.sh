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
## - Pod Overrides
##    - Most of my workloads are flexible, but some need specific requirements

## Clean-up previous demo resources
kubectl get nodepool --no-headers | tr -s " " | cut -d " " -f1 | xargs kubectl delete nodepool > /dev/null 2>&1 || :
kubectl get ec2nodeclass --no-headers | tr -s " " | cut -d " " -f1 | xargs kubectl delete ec2nodeclass > /dev/null 2>&1 || :
kubectl delete all -l demo > /dev/null 2>&1

cat << EOF > /tmp/node-pool-constrained.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-consolidation
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
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

cmd "cat /tmp/node-pool-constrained.yaml"
cmd "kubectl apply -f /tmp/node-pool-constrained.yaml"

cat << EOF > /tmp/demo-inflate-demo-consolidation.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-consolidation-1
  labels:
    demo: demo-consolidation
spec:
  selector:
    matchLabels:
      app: inflate-demo-consolidation-1
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-consolidation-1
        demo: demo-consolidation
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-consolidation
        resources:
          requests:
            cpu: "1"
            memory: 256M
EOF

cmd "cat /tmp/demo-inflate-demo-consolidation.yaml"
cmd "kubectl apply -f /tmp/demo-inflate-demo-consolidation.yaml"

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-consolidation-2
  labels:
    demo: demo-consolidation
spec:
  selector:
    matchLabels:
      app: inflate-demo-consolidation-2
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-consolidation-2
        demo: demo-consolidation
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-consolidation
        resources:
          requests:
            cpu: "1"
            memory: 256M
EOF

cmd "kubectl scale deployment inflate-demo-consolidation-1 --replicas=50"
cmd "kubectl scale deployment inflate-demo-consolidation-2 --replicas=50"

input_cmd "AMD_OD_COST="

cat << EOF > /tmp/demo-consolidation-arm64.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-consolidation
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
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

input_cmd "ARM_OD_COST="
cmd "echo \"1 - \$ARM_OD_COST / \$AMD_OD_COST \" | bc -l "

cat << EOF > /tmp/demo-consolidation-spot.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-consolidation
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
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

cmd "cat /tmp/demo-consolidation-spot.yaml"
cmd "kubectl apply -f /tmp/demo-consolidation-spot.yaml"

input_cmd "SPOT_COST="
cmd "echo \"1 - \$SPOT_COST / \$ARM_OD_COST\" | bc -l "
cmd "echo \"1 - \$SPOT_COST / \$AMD_OD_COST\" | bc -l "

cat << EOF > /tmp/deployment-pod-override-instance-type.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-pod-override-instance-type
  labels:
    demo: demo-pod-overrides
spec:
  selector:
    matchLabels:
      app: inflate-demo-pod-override-instance-type
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-pod-override-instance-type
        demo: demo-pod-overrides
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-pod-overrides
        resources:
          requests:
            cpu: "1"
            memory: 256M
      nodeSelector:
        node.kubernetes.io/instance-type: c5.xlarge
        karpenter.sh/capacity-type: on-demand
EOF

cmd "cat /tmp/deployment-pod-override-instance-type.yaml"
cmd "kubectl apply -f /tmp/deployment-pod-override-instance-type.yaml"
cmd "kubectl scale deployment inflate-demo-pod-override-instance-type --replicas=10"
cmd "kubectl scale deployment inflate-demo-pod-override-instance-type --replicas=0"

cmd "kubectl scale deployment inflate-demo-consolidation-1 --replicas=0"
cmd "kubectl scale deployment inflate-demo-consolidation-2 --replicas=0"

cmd "kubectl delete nodes -l 'karpenter.sh/nodepool'"
