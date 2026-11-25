#!/bin/bash
set -e

echo "1. Instalando Docker e dependências..."
sudo apt-get update
sudo apt-get install -y curl wget ca-certificates conntrack docker.io nginx
sudo usermod -aG docker $USER

echo "2. Instalando kubectl e Minikube..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm -f minikube-linux-amd64

echo "3. Iniciando Minikube e habilitando Ingress..."
sg docker -c "minikube start --driver=docker --cpus=4 --memory=7168m"
sg docker -c "minikube addons enable ingress"

echo "4. Aguardando Ingress Controller ficar pronto..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo "5. Aplicando manifestos das aplicações e Ingress..."
kubectl apply -f k8s/apps.yaml
kubectl apply -f k8s/ingress.yaml

echo "6. Configurando Nginx da VM (porta 8018) -> Ingress do Minikube..."
MINIKUBE_IP=$(minikube ip)
sudo tee /etc/nginx/sites-available/poi-k8s <<EOF
server {
    listen 8018;
    server_name _;

    location / {
        proxy_pass http://${MINIKUBE_IP}:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/poi-k8s /etc/nginx/sites-enabled/poi-k8s
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

echo "=== CONCLUÍDO! ==="
kubectl get pods,svc,ingress