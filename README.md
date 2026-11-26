# Infraestrutura Kubernetes: Atividade 5 (POI)

**Disciplina:** Provisionamento e Otimização de Infraestrutura (POI), UFCG / LSD
**Grupo:** Grupo 18
**Integrantes:**
* [Nome Completo 1] - [Matrícula: 000000000]
* Heitor de Souza Alves - 123110811
* [Nome Completo 3] - [Matrícula: 000000000]

---

## 1. Visão geral e arquitetura

Este repositório contém o código das três aplicações (CPU-bound, Memory-bound e I/O-bound), os Dockerfiles, os manifestos Kubernetes e os scripts usados para executá-las em um cluster **Minikube** hospedado em uma VM da nuvem **OpenStack** do LSD/UFCG. As imagens são construídas a partir do código deste repositório, e não baixadas de registries externos.

### Fluxo de tráfego externo

```
Cliente externo
      │
      ▼  http://150.165.85.77:8018/{cpu|memory|io}
OpenStack Load Balancer (poi-atividades)
      │  Listener TCP :8018 -> pool-app-grupo-18 -> 10.5.8.252:8018
      ▼
VM OpenStack (vm-k8s-grupo-18, 10.5.8.252)
      │  socat (serviço systemd): :8018 -> <minikube-ip>:30080
      ▼
Service app-gateway (NodePort 30080)
      │
      ▼
Pods app-gateway (nginx, 2 réplicas)
      ├── /cpu    ──► Service app-cpu    (ClusterIP :8080) ──► Deployment app-cpu    (2 réplicas)
      ├── /memory ──► Service app-memory (ClusterIP :8080) ──► Deployment app-memory (2 réplicas)
      └── /io     ──► Service app-io     (ClusterIP :8080) ──► StatefulSet app-io    (2 réplicas, PVC 2Gi cada)
```

Somente o gateway é exposto fora do cluster. Os três backends são acessíveis apenas por Services `ClusterIP`.

---

## 2. Infraestrutura na nuvem OpenStack

### 2.1 Limpeza de recursos anteriores
Antes de criar o novo ambiente, foram removidos os recursos do Grupo 18 das atividades anteriores (VMs, volumes, snapshots e members de pool que apontavam para a VM antiga). Recursos de outros grupos e do professor não foram alterados.

### 2.2 Criação da VM `vm-k8s-grupo-18`
* **Flavor:** `general.large` (4 vCPUs, 8 GB de RAM)
* **Imagem:** `ubuntu-24.04` LTS
* **Keypair:** `grupo-18`
* **Security group:** `sg-grupo-18`
* **Rede:** `provider`
* **IP privado:** `10.5.8.252`

A primeira VM foi criada com o flavor `general.medium` (IP `10.5.10.15`) e substituída por uma `general.large`, para atender o mínimo de 4 vCPUs e 8 GB de RAM.

```
openstack server create \
  --flavor general.large \
  --image ubuntu-24.04 \
  --key-name grupo-18 \
  --security-group sg-grupo-18 \
  --network provider \
  --wait vm-k8s-grupo-18

openstack server show vm-k8s-grupo-18 -c addresses
```

### 2.3 Security group
Além do SSH (22), foi liberada a porta TCP **8018**, usada pelo Load Balancer para alcançar a VM:

```
openstack security group rule create --proto tcp --dst-port 8018 --ingress sg-grupo-18
```

### 2.4 Acesso SSH pelo Load Balancer
As VMs da rede `provider` possuem apenas IP interno. O acesso administrativo é feito pelo Load Balancer compartilhado `poi-atividades` (`150.165.85.77`):

* **Listener:** `listener-ssh-grupo18`, TCP, porta externa `2218`
* **Pool:** `8328d252-36c7-4124-84f9-846a98db4b42`
* **Member:** `10.5.8.252:22`

```
openstack loadbalancer member create \
  --subnet-id 17de9c72-e5dc-4da0-ae0a-013f7e42400e \
  --address 10.5.8.252 \
  --protocol-port 22 \
  --wait 8328d252-36c7-4124-84f9-846a98db4b42

ssh -i grupo-18.pem -p 2218 ubuntu@150.165.85.77
```

---

## 3. Instalação e configuração do cluster Kubernetes

Os scripts ficam em `scripts/`:

| Script | Função |
|---|---|
| `01-install.sh` | Instala Docker, kubectl, Minikube, socat e git e adiciona o usuário ao grupo `docker` |
| `02-start-minikube.sh` | Cria o cluster com `minikube start --driver=docker --cpus=4 --memory=6144` |
| `03-build-deploy.sh` | Constrói as 4 imagens com `minikube image build` e aplica os manifestos de `k8s/` |
| `04-forward.sh` | Cria o serviço systemd com `socat`, encaminhando a porta 8018 da VM ao NodePort 30080 |

---

## 4. Deploy das aplicações e justificativa dos workloads

As imagens são construídas no próprio Minikube a partir do código do repositório (`services/`), com `imagePullPolicy: Never`:

* `app-cpu:1.0`: calcula a soma de `i * i` para `n` iterações (CPU-bound), `GET /cpu?n=`
* `app-memory:1.0`: aloca e soma uma matriz `size x size` em RAM (memory-bound), `GET /memory?size=`
* `app-io:1.0`: executa ciclos de escrita com `fsync` e leitura de blocos de 1 MB em disco (I/O-bound), `GET /io?size=`
* `app-gateway:1.0`: nginx que roteia `/cpu`, `/memory` e `/io` para os Services internos

### 4.1 Objetos Kubernetes e justificativas (`k8s/`)

| Aplicação | Objeto | Réplicas | requests | limits |
|---|---|---|---|---|
| app-cpu | Deployment | 2 | 250m / 64Mi | 1 CPU / 256Mi |
| app-memory | Deployment | 2 | 100m / 256Mi | 500m / 1Gi |
| app-io | StatefulSet + PVC | 2 | 100m / 128Mi | 500m / 512Mi |
| app-gateway | Deployment | 2 | 50m / 32Mi | 200m / 128Mi |

1. **`Deployment` para `app-cpu` e `app-memory`.** As duas aplicações não dependem de estado persistente: cada requisição é independente e os logs em `/data` são auxiliares (volume `emptyDir`). O Deployment fornece self-healing, rolling update e escala simples, e as 2 réplicas dão disponibilidade caso um pod seja recriado.

2. **`StatefulSet` com `volumeClaimTemplates` para `app-io`.** É a aplicação que grava dados em disco de forma relevante (arquivos de 1 MB com `fsync` e logs). Cada réplica recebe seu próprio PVC de 2Gi (`data-app-io-0`, `data-app-io-1`) e uma identidade estável (`app-io-0`, `app-io-1`). Assim, os logs e o volume sobrevivem a reinícios do pod e não se misturam entre réplicas. O Service headless `app-io-headless` dá o nome DNS estável a cada pod.

3. **`requests` e `limits` em todos os containers.** O limite de memória do `app-memory` (1Gi) faz com que um `size` muito grande cause apenas o OOMKill do pod, e não do nó. O `app-cpu` tem teto de 1 CPU, que é o máximo aproveitável por um processo Python limitado pelo GIL.

4. **Probes de readiness e liveness com `timeoutSeconds` e `failureThreshold` folgados.** Requisições pesadas (CPU, memória e I/O com `fsync`) podem bloquear o pod por bastante tempo. Probes agressivas fariam o Kubernetes matar pods saudáveis durante a carga.

5. **Services `ClusterIP` para os backends e `NodePort` (30080) só para o gateway.** Uma única porta de entrada simplifica o Load Balancer e evita abrir portas desnecessárias. Os nomes `app-cpu`, `app-memory` e `app-io` são usados pelo `nginx.conf` do gateway.

6. **Gateway nginx como Deployment.** Faz o roteamento por caminho (`/cpu`, `/memory`, `/io`) com o `nginx.conf` versionado em `services/gateway/`, e responde `online` na raiz `/` (usada também como readiness probe). O `proxy_read_timeout` de 300 s sustenta requisições longas.

---

## 5. Exposição externa e Load Balancer

### 5.1 Encaminhamento na VM (`socat` + systemd)
Com o driver `docker`, o IP do Minikube (`minikube ip`, ex.: `192.168.49.2`) só é alcançável de dentro da VM. O script `scripts/04-forward.sh` cria o serviço `minikube-fwd`, que escuta na porta **8018** da VM e encaminha para `<minikube-ip>:30080`:

```
sudo systemctl status minikube-fwd --no-pager
sudo ss -tlnp | grep 8018
curl "http://localhost:8018/"
```

### 5.2 Load Balancer `poi-atividades`
O pool da aplicação do Grupo 18 (`pool-app-grupo-18`) aponta para a VM na porta 8018:

```
openstack loadbalancer member create \
  --subnet-id 17de9c72-e5dc-4da0-ae0a-013f7e42400e \
  --address 10.5.8.252 \
  --protocol-port 8018 \
  --wait pool-app-grupo-18

openstack loadbalancer member list pool-app-grupo-18
```

O member deve ficar com `operating_status: ONLINE` após o health check.

### 5.3 Validação remota

```
curl "http://150.165.85.77:8018/"
curl "http://150.165.85.77:8018/cpu?n=20000000"
curl "http://150.165.85.77:8018/memory?size=1000"
curl "http://150.165.85.77:8018/io?size=10"
```

Respostas esperadas: `online`, e JSON com `"type": "CPU-bound"`, `"memory-bound"` e `"I/O-bound"`.

### 5.4 Evidências adicionais

```
kubectl get pods,svc,pvc -o wide
kubectl exec app-io-0 -- tail -n 5 /data/logs/io.log

# self-healing: apagar os pods do cpu e acompanhar a recriação
kubectl delete pod -l app=app-cpu --wait=false
kubectl get pods -w
```

---

## 6. Limitações conhecidas e melhorias futuras

* O `socat` guarda o IP do Minikube no arquivo do serviço. Se o IP mudar, é preciso rodar `04-forward.sh` novamente.
* Após reiniciar a VM, o Minikube precisa de `minikube start` manual, e o `minikube-fwd` só funciona depois disso.
* O gateway nginx faz o papel de um Ingress. Uma evolução natural é usar o recurso nativo `Ingress` com o addon do Minikube.
* O StatefulSet do I/O usa o storage class `standard` do Minikube (hostPath), adequado a um ambiente de laboratório, não de produção.

---

## 7. Estrutura do repositório

```
.
├── services/
│   ├── cpu/        # server.py + Dockerfile
│   ├── memory/     # server.py + Dockerfile
│   ├── io/         # server.py + Dockerfile
│   └── gateway/    # nginx.conf + Dockerfile
├── k8s/
│   ├── cpu.yaml        # Deployment + Service
│   ├── memory.yaml     # Deployment + Service
│   ├── io.yaml         # StatefulSet + PVCs + Services (ClusterIP e headless)
│   └── gateway.yaml    # Deployment + Service NodePort 30080
├── scripts/
│   ├── 01-install.sh
│   ├── 02-start-minikube.sh
│   ├── 03-build-deploy.sh
│   └── 04-forward.sh
├── openstack/      # comandos do Load Balancer e do security group
├── docs/           # documentação e prints
└── requirements.txt
```
