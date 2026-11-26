#!/bin/bash
# Sobe o cluster Kubernetes (Minikube, driver docker)
set -e
minikube start --driver=docker --cpus=4 --memory=6144
kubectl get nodes
kubectl get pods -A
