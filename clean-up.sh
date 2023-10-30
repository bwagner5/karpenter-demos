#!/usr/bin/env bash
set -euo pipefail
set -x
kubectl delete nodepool default > /dev/null 2>&1 || :
kubectl delete ec2nodeclass default > /dev/null 2>&1 || :
kubectl delete all -l demo > /dev/null 2>&1
