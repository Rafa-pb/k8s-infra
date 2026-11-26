# Infraestrutura Kubernetes — Atividade 5 (POI)

**Disciplina:** Provisionamento e Otimização de Infraestrutura (POI) — UFCG / LSD  
**Grupo:** Grupo 18  
**Integrantes:**
* [Nome Completo 1] — Matrícula: [000000000]
* [Nome Completo 2] — Matrícula: [000000000]
* [Nome Completo 3] — Matrícula: [000000000]

---

## 1. Visão Geral e Arquitetura

Este repositório contém os scripts de automação e manifestos Kubernetes utilizados para o deploy e exposição externa de três aplicações backend com distintos perfis computacionais (**CPU-bound**, **Memory-bound** e **I/O-bound**) em um cluster Kubernetes (**Minikube**) hospedado na nuvem privada **OpenStack** do LSD/UFCG.

### Fluxo de Tráfego Externo

```text
Cliente Externo
      │
      ▼  [http://150.165.85.77:8018/](http://150.165.85.77:8018/){cpu|memory|io}
OpenStack Load Balancer (poi-atividades)
      │  Pool: pool-app-grupo-18 (TCP :8018 -> 10.5.8.252:8018)
      ▼
VM OpenStack (vm-k8s-grupo-18 - 10.5.8.252)
      │  Nginx Reverse Proxy (:8018 -> <minikube-ip>:80)
      ▼
Kubernetes Ingress Controller (NGINX - rewrite-target: /$2)
      ├── /cpu    ──► poi-app-cpu-service (ClusterIP :8000)    ──► Pods poi-app-cpu (2 réplicas)
      ├── /memory ──► poi-app-memory-service (ClusterIP :8000) ──► Pods poi-app-memory (2 réplicas)
      └── /io     ──► poi-app-io-service (ClusterIP :8000)     ──► Pods poi-app-io (2 réplicas)
```

---

## 2. Limpeza da Infraestrutura Anterior e Provisionamento na Nuvem OpenStack

### 2.1 Limpeza de Recursos Anteriores
Antes de provisionar o ambiente do Kubernetes no projeto `provisionamento`, foram removidos os artefatos da atividade anterior pertencentes ao Grupo 18 para liberar cota computacional e manter o ambiente organizado:
* **Snapshot removido:** `snap-vol-grupo-18`
* **Volume removido:** `vol-grupo-18`
* **Instância removida:** `vm-grupo-18` (IP antigo `10.5.11.53`)

### 2.2 Criação da Nova Instância (`vm-k8s-grupo-18`)
Para comportar o cluster Minikube e as réplicas das aplicações com folga de memória e processamento, foi criada uma nova instância na rede `provider`:
* **Nome da VM:** `vm-k8s-grupo-18`
* **Flavor:** `general.large` (4 vCPUs, 8 GB RAM)
* **Imagem:** `ubuntu-24.04` LTS
* **Keypair:** `grupo-18`
* **Security Group:** `sg-grupo-18` (regras TCP de entrada liberadas para portas `22` e `8018`)
* **IP Privado atribuído:** `10.5.8.252`

Comando executado via OpenStack CLI:

```bash
openstack server create \
  --flavor general.large \
  --image ubuntu-24.04 \
  --key-name grupo-18 \
  --security-group sg-grupo-18 \
  --network provider \
  --wait vm-k8s-grupo-18
```

### 2.3 Atualização do Acesso SSH no Load Balancer (`poi-atividades`)
Como as instâncias da rede `provider` possuem apenas IPs internos, o acesso administrativo via SSH foi configurado no Load Balancer compartilhado `poi-atividades` (`150.165.85.77`):
* **Listener SSH:** `listener-ssh-grupo18` (Porta externa `2218`, protocolo `TCP`)
* **Pool SSH:** `8328d252-36c7-4124-84f9-846a98db4b42`
* **Atualização de Member:** Remoção do IP antigo (`10.5.11.53`) e adição do membro `10.5.8.252` na porta `22`.

> *[Inserir prints da criação da VM `vm-k8s-grupo-18`, regras do `sg-grupo-18` e atualização do pool SSH no Load Balancer]*

---

## 3. Instalação e Configuração do Cluster Kubernetes (Minikube)

O script `scripts/deploy-k8s.sh` automatiza todo o provisionamento do cluster dentro da VM `vm-k8s-grupo-18`:

1. **Instalação do Container Runtime e Dependências:** Instalação do `docker.io`, `conntrack`, `curl` e `nginx`.
2. **Instalação das Ferramentas Kubernetes:** Download e instalação dos binários oficiais do `kubectl` e `minikube`.
3. **Inicialização do Cluster:**

   ```bash
   minikube start --driver=docker --cpus=4 --memory=7168m
   ```

   *(Foram alocados 4 vCPUs e 7168 MB de RAM para o nó do Minikube, reservando ~1 GB de RAM para o sistema operacional hospedeiro Ubuntu 24.04 e o proxy reverso Nginx, prevenindo falhas por falta de memória).*
4. **Habilitação do Ingress Controller:**

   ```bash
   minikube addons enable ingress
   ```

> *[Inserir prints da execução do `minikube status`, `kubectl get nodes` e `kubectl get pods -A`]*

---

## 4. Deploy das Aplicações e Justificativa dos Workloads

As três aplicações foram previamente conteinerizadas (FastAPI + Uvicorn na porta `8000`) e publicadas no Docker Hub:
* **CPU-bound (`andretharssys/poi-app-cpu:latest`):** Executa `n` iterações matemáticas intensivas acumulando `i * i`.
* **Memory-bound (`andretharssys/poi-app-memory:latest`):** Aloca e soma os elementos de uma matriz bidimensional `size x size` em memória RAM.
* **I/O-bound (`andretharssys/poi-app-io:latest`):** Realiza `size` ciclos de escrita e leitura sequencial de blocos de 1 MB em disco temporário.

### Justificativa das Escolhas de Objetos Kubernetes (`k8s/apps.yaml` e `k8s/ingress.yaml`)

1. **`Deployment` (com `replicas: 2` para cada aplicação):**
   * **Natureza Stateless:** As três aplicações processam requisições HTTP de forma independente, sem necessidade de manter estado persistente vinculado à identidade de rede ou armazenamento exclusivo de um pod específico (o que torna desnecessário o uso de `StatefulSet`).
   * **Alta Disponibilidade e Auto-recuperação:** O controlador de `Deployment` garante que 2 réplicas de cada serviço permaneçam em execução, recriando automaticamente qualquer pod caso ocorra falha sob estresse.
   * **Gerenciamento de Recursos (`requests` e `limits`):** Foram definidos limites explícitos de CPU e memória por container (destacando-se o limite de `2Gi` para `poi-app-memory`), evitando que um único pod consuma toda a memória do nó e cause *OOMKilled* em cascata.

2. **`Service` do tipo `ClusterIP`:**
   * Como o ponto de entrada único do cluster é gerenciado pelo `Ingress`, expor cada aplicação internamente via `ClusterIP` na porta `8000` fornece um endereço IP virtual estável e balanceamento de carga interno entre as réplicas de cada `Deployment`, sem abrir portas desnecessárias no nó.

3. **`Ingress` (`nginx` com `rewrite-target`):**
   * Permite rotear o tráfego HTTP de uma única porta de entrada para os três microsserviços distintos com base no caminho da URL (`/cpu`, `/memory` e `/io`).
   * A anotação `nginx.ingress.kubernetes.io/rewrite-target: /$2` combinada com os caminhos `/cpu(/|$)(.*)`, `/memory(/|$)(.*)` e `/io(/|$)(.*)` remove o prefixo da rota antes de encaminhar a requisição ao container, garantindo compatibilidade com os endpoints raiz (`/`) implementados no FastAPI.

> *[Inserir prints da aplicação dos manifestos (`kubectl apply -f k8s/`) e da saída de `kubectl get pods,svc,ingress`]*

---

## 5. Exposição Externa e Configuração do Load Balancer

### 5.1 Proxy Reverso na VM (`Nginx` na porta `8018`)
Como o Minikube utiliza o driver `docker` em uma sub-rede isolada interna à VM, o IP do Ingress Controller não é diretamente alcançável pela rede externa `provider`. Para expor o cluster para o Load Balancer do OpenStack, o script `scripts/deploy-k8s.sh` configura o **Nginx** na VM `vm-k8s-grupo-18` escutando na porta `8018` e encaminhando todas as requisições para `http://$(minikube ip):80`.

### 5.2 Configuração do Load Balancer `poi-atividades`
No OpenStack, o pool da aplicação do Grupo 18 (`pool-app-grupo-18`, ID `73c59098-c01c-42a9-ab30-efcc02b74d5e`) foi atualizado para apontar para a nova VM na porta `8018`:

```bash
# Remoção do membro da atividade anterior (10.5.11.53:8080)
openstack loadbalancer member delete pool-app-grupo-18 909191dc-bc55-4edb-9745-0ac72399b964

# Adição da VM do cluster Kubernetes (10.5.8.252:8018)
openstack loadbalancer member create \
  --subnet-id 17de9c72-e5dc-4da0-ae0a-013f7e42400e \
  --address 10.5.8.252 \
  --protocol-port 8018 \
  --wait pool-app-grupo-18
```

### 5.3 Validação Remota
Com o membro ativo (`ACTIVE` / `ONLINE`) no Load Balancer `poi-atividades` (`150.165.85.77`), o acesso externo às três aplicações foi validado remotamente:

```bash
# Teste CPU-bound
curl "[http://150.165.85.77:8018/cpu?n=3000000](http://150.165.85.77:8018/cpu?n=3000000)"

# Teste Memory-bound
curl "[http://150.165.85.77:8018/memory?size=1500](http://150.165.85.77:8018/memory?size=1500)"

# Teste I/O-bound
curl "[http://150.165.85.77:8018/io?size=20](http://150.165.85.77:8018/io?size=20)"
```

> *[Inserir prints do `openstack loadbalancer member list pool-app-grupo-18` e das respostas JSON retornadas pelos três comandos `curl` externos]*

---

## 6. Estrutura do Repositório

```text
k8s-infra/
├── README.md               # Documentação completa da infraestrutura, deploy e validação
├── k8s/
│   ├── apps.yaml           # Deployments (2 réplicas) e Services (ClusterIP) das 3 aplicações
│   └── ingress.yaml        # Regras de roteamento L7 (/cpu, /memory, /io) com rewrite-target
└── scripts/
    └── deploy-k8s.sh       # Automação de instalação (Docker, kubectl, Minikube, Nginx) e deploy
```
