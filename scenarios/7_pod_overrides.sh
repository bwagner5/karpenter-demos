#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "${SCRIPTPATH}/../lib/utils.sh"

## Pod Overrides DEMO:
## This demo shows how you can customize your flexibility to meet your needs
## Points:
##  - NodePool requirements are layered with pod requirements

## Clean-up previous demo resources
kubectl get nodepool --no-headers | tr -s " " | cut -d " " -f1 | xargs kubectl delete nodepool > /dev/null 2>&1 || :
kubectl get ec2nodeclass --no-headers | tr -s " " | cut -d " " -f1 | xargs kubectl delete ec2nodeclass > /dev/null 2>&1 || :
kubectl delete all -l demo > /dev/null 2>&1 || :

cat << EOF > /tmp/node-pool-standard.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  labels:
    demo: demo-pod-overrides
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5s
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-pod-overrides
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
    demo: demo-pod-overrides
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
  name: inflate-demo-pod-overrides
  labels:
    demo: demo-pod-overrides
spec:
  selector:
    matchLabels:
      app: inflate-demo-pod-overrides
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-pod-overrides
        demo: demo-pod-overrides
    spec:
      containers:
      - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        name: inflate-demo-pod-overrides
        resources:
          requests:
            cpu: "1"
            memory: 256M
EOF

cmd "cat /tmp/deployment-standard.yaml"
cmd "kubectl apply -f /tmp/deployment-standard.yaml"
cmd "kubectl scale deployment inflate-demo-pod-overrides --replicas=10"
cmd "kubectl scale deployment inflate-demo-pod-overrides --replicas=0"

cat << EOF > /tmp/deployment-pod-override-od.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate-demo-pod-override-od
  labels:
    demo: demo-pod-overrides
spec:
  selector:
    matchLabels:
      app: inflate-demo-pod-override-od
  replicas: 0
  template:
    metadata:
      labels:
        app: inflate-demo-pod-override-od
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
        karpenter.sh/capacity-type: on-demand
EOF

cmd "cat /tmp/deployment-pod-override-od.yaml"
cmd "kubectl apply -f /tmp/deployment-pod-override-od.yaml"
cmd "kubectl scale deployment inflate-demo-pod-override-od --replicas=10"
cmd "kubectl scale deployment inflate-demo-pod-override-od --replicas=0"


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
        node.kubernetes.io/instance-type: c4.xlarge
EOF

cmd "cat /tmp/deployment-pod-override-instance-type.yaml"
cmd "kubectl apply -f /tmp/deployment-pod-override-instance-type.yaml"
cmd "kubectl scale deployment inflate-demo-pod-override-instance-type --replicas=10"
cmd "kubectl scale deployment inflate-demo-pod-override-instance-type --replicas=0"

