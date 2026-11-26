#!/bin/bash
# Servico systemd que encaminha a porta 30080 da VM para o NodePort do Minikube
set -e
MINIKUBE_IP=$(minikube ip)
sudo tee /etc/systemd/system/minikube-fwd.service > /dev/null <<UNIT
[Unit]
Description=Forward 30080 para o Minikube
After=docker.service network-online.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:30080,fork,reuseaddr TCP:${MINIKUBE_IP}:30080
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now minikube-fwd
sudo systemctl status minikube-fwd --no-pager
