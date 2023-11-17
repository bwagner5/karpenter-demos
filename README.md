# Karpenter Demos

## Install ec2-spot-interrupter

```
brew install aws/tap/ec2-spot-interrupter
```

## Start EKS Node Viewer:

```
eks-node-viewer -node-selector karpenter.sh/nodepool -extra-labels topology.kubernetes.io/zone
```

## Demo Videos

bwag.me/cmp328/index.html
