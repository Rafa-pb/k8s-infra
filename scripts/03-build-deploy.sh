#!/bin/bash
# Builda as imagens dentro do Minikube e aplica os manifestos
set -e
cd "$(dirname "$0")/.."
pwd
ls services

minikube image build -t app-cpu:1.0     -f services/cpu/Dockerfile .
minikube image build -t app-memory:1.0  -f services/memory/Dockerfile .
minikube image build -t app-io:1.0      -f services/io/Dockerfile .
minikube image build -t app-gateway:1.0 -f services/gateway/Dockerfile .

# backends primeiro: o nginx resolve os nomes ao iniciar
kubectl apply -f k8s/cpu.yaml -f k8s/memory.yaml -f k8s/io.yaml
kubectl rollout status deploy/app-cpu --timeout=180s
kubectl rollout status deploy/app-memory --timeout=180s
kubectl rollout status statefulset/app-io --timeout=180s
kubectl apply -f k8s/gateway.yaml
kubectl rollout status deploy/app-gateway --timeout=120s
kubectl get pods,svc,pvc -o wide
