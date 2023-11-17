#!/usr/bin/env bash
set -euo pipefail
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
source "${SCRIPTPATH}/../lib/utils.sh"

## Spot Interruption DEMO:
## This demo shows how Karpenter handles spot interruptions
## Points:
##  - Spot Interruptions are handled by Karpenter natively
##  - Instances are prespun when an interruption arrives to minimize downtime

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
    demo: demo-spot-interruption
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5s
    expireAfter: Never
  template:
    metadata:
      labels:
        demo: demo-spot-interruption
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
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
    demo: demo-spot-interruption
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

cat << EOF > /tmp/deployment-ahem.yaml
 apiVersion: apps/v1
 kind: Deployment
 metadata:
   name: ahem
   labels:
     app: ahem
     demo: demo-spot-interruption
 spec:
   selector:
     matchLabels:
       app: ahem
   replicas: 0
   template:
     metadata:
       labels:
         app: ahem
         demo: demo-spot-interruption
     spec:
       terminationGracePeriodSeconds: 45
       containers:
       - image: public.ecr.aws/brandonwagner/ahem:v0.0.3
         env:
          - name: delay
            value: "40s"
         name: ahem
         resources:
           requests:
             cpu: "1"
             memory: 256M
       topologySpreadConstraints:
       - labelSelector:
           matchLabels:
             app: ahem
         maxSkew: 1
         topologyKey: topology.kubernetes.io/zone
         whenUnsatisfiable: DoNotSchedule
EOF

cmd "cat /tmp/deployment-ahem.yaml"
cmd "kubectl apply -f /tmp/deployment-ahem.yaml"

cmd "kubectl scale deployment ahem --replicas=10"

cmd "ec2-spot-interrupter --interactive"

cmd "kubectl scale deployment ahem --replicas=0"

