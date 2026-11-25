# Infraestrutura Kubernetes — Atividade 5

**Grupo:** Grupo 18  
**Alunos:** [Preencher nomes completos]  
**Matrículas:** [Preencher matrículas]  

---

## 1. Configuração da VM e Ambiente da Cloud
* **Limpeza de recursos anteriores:** Remoção do snapshot (`snap-vol-grupo-18`), volume (`vol-grupo-18`) e instância anterior (`vm-grupo-18`) no projeto `provisionamento` do OpenStack (LSD/UFCG), preservando os recursos compartilhados e dos demais grupos.
* **Provisionamento da nova VM:** Criação da instância `vm-k8s-grupo-18` com imagem `ubuntu-24.04` LTS, flavor com 4 vCPUs e 8 GB de RAM, associada ao par de chaves `grupo-18` e ao grupo de segurança `sg-grupo-18`.
* **Configuração de rede e Load Balancer:** Liberação das portas necessárias no *Security Group* e configuração de listeners, pools, health monitors e members no Load Balancer compartilhado `poi-atividades` (`150.165.85.77`) direcionando o tráfego externo para a VM do grupo.
* *[Inserir prints da criação da VM, Security Group e Load Balancer]*

---

## 2. Deploy e Configuração do Cluster Kubernetes
* **Instalação das ferramentas:** Instalação do Docker Engine (utilizado como driver de container do Minikube), `kubectl` e `minikube` via script `scripts/setup-k8s.sh`.
* **Inicialização do cluster:** Execução de `minikube start --driver=docker --cpus=4 --memory=7168m`, reservando ~1 GB de RAM para o sistema operacional hospedeiro (Ubuntu 24.04) a fim de evitar *OOMKilled* e garantir estabilidade.
* **Validação:** Verificação do nó `minikube` em estado `Ready` (`kubectl get nodes`) e dos pods de sistema no namespace `kube-system` (`kubectl get pods -A`).
* *[Inserir prints do cluster ativo]*

---

## 3. Deploy das Aplicações e Acesso Externo
### Justificativa da Escolha de Workloads
Para as três aplicações (`poi-app-cpu`, `poi-app-memory` e `poi-app-io`), optou-se pelo workload **`Deployment`** associado a objetos **`Service` (`NodePort`)**:
1. **Natureza Stateless:** As aplicações processam requisições HTTP de forma independente (cálculos matemáticos em CPU, alocação matricial em RAM e operações temporárias de escrita/leitura em disco), sem necessidade de armazenamento persistente vinculado à identidade de um pod específico (o que dispensou o uso de `StatefulSet`).
2. **Disponibilidade e Autorrecuperação:** O `Deployment` mantém múltiplas réplicas ativas (`replicas: 2`) e recria automaticamente qualquer pod que falhe ou sofra reinicialização sob carga.
3. **Atualizações Controladas e Limites de Recursos:** Permite definir `requests` e `limits` de CPU e memória por container (especialmente importante na aplicação *memory-bound*) e realizar *rolling updates* sem indisponibilidade.

### Etapas de Deploy e Exposição Externa
1. Aplicação dos manifestos YAML localizados em `k8s/` via `kubectl apply -f k8s/`.
2. Encaminhamento do tráfego externo da VM para os serviços do Minikube (`NodePorts` `30081`, `30082` e `30083`).
3. Acesso remoto validado através do IP público do Load Balancer do OpenStack (`150.165.85.77`) para os endpoints `/cpu`, `/memory` e `/io`.
* *[Inserir prints de `kubectl get pods,svc` e das requisições externas respondendo via IP do Load Balancer]*