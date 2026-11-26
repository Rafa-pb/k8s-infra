#!/bin/bash
# Instala Docker, kubectl, Minikube, socat e git na VM Ubuntu 24.04
set -e
sudo apt-get update
sudo apt-get install -y docker.io curl conntrack socat git
sudo usermod -aG docker "$USER"
sudo snap install kubectl --classic
curl -Lo /tmp/minikube https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install /tmp/minikube /usr/local/bin/minikube
echo "Pronto. Saia da sessao SSH e entre de novo para o grupo docker valer."
