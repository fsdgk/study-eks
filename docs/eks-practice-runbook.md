# Spring PetClinic EKS 실습 Runbook

최종 확인일: 2026-07-29

대상 프로젝트: `jangwoolab/spring-petclinic`

AWS 리전: 서울 `ap-northeast-2`

이 문서는 AWS 콘솔에서 처리할 수 있는 작업은 콘솔을 우선 사용하고, 과제에서 CLI 사용이 명시되었거나 콘솔만으로 완료할 수 없는 작업은 명령어를 사용한다. 명령 실행 결과와 AWS 콘솔 화면을 단계별로 캡처하여 Notion에 정리한 뒤 `1조_홍길동.pdf` 형식으로 내보낸다.

> 비용 주의: EKS 제어 영역, EC2 노드, Load Balancer, NAT Gateway, ECR 저장소에는 비용이 발생할 수 있다. 실습 종료 후 9단계 정리 절차를 반드시 완료한다.

## GitHub 공개 저장소 최초 배포

현재 프로젝트를 본인 GitHub 계정의 공개 저장소 `study-eks`로 올릴 때 한 번만 실행한다.

### GitHub CLI 설치와 인증 - Windows PowerShell

```powershell
winget install --id GitHub.cli
gh auth login --web --git-protocol https
gh auth status
```

브라우저 인증 화면에서 본인 계정 로그인을 완료한다. Token 값은 문서나 캡처에 포함하지 않는다.

### Git 제외 규칙 확인

```powershell
git check-ignore -v `
  .env `
  .env.local `
  docs/superpowers/example.md

git status --short
```

`.env`, `.env.*`, `docs/superpowers/`가 ignore 되는지 확인한다.

### 공개 저장소 생성과 Push

```powershell
gh repo create study-eks `
  --public `
  --source=. `
  --remote=origin `
  --push `
  --description "Spring PetClinic EKS practice project"

git remote -v
git status --short --branch
gh repo view --web
```

이미 GitHub에 빈 `study-eks` 저장소를 직접 만들었다면 다음 방식으로 연결한다.

```powershell
git remote add origin https://github.com/YOUR_GITHUB_ID/study-eks.git
git push -u origin main
```

성공 기준:

- GitHub 저장소 Visibility가 Public
- 기본 브랜치가 `main`
- `.env`와 `docs/superpowers/`가 GitHub 파일 목록에 없음
- `docs/eks-practice-runbook.md`가 GitHub에서 보임

---

## 0. 시작 전 준비

### 로컬 Windows 준비

- Docker Desktop 설치 및 로그인
- Docker Desktop의 Kubernetes 활성화
- `kubectl`, AWS CLI v2 설치
- Docker Hub 계정
- AWS 실습 계정과 서울 리전 사용 권한
- 이 프로젝트 폴더에서 PowerShell 실행

PowerShell에서 상태를 확인한다.

```powershell
docker version
kubectl version --client
aws --version
git status
```

AWS 콘솔 오른쪽 위 리전이 **서울(ap-northeast-2)** 인지 확인한다.

### 캡처 원칙

- 비밀번호, Access Key, Secret Key, 세션 토큰, `.env` 내용은 캡처하지 않는다.
- 캡처에는 실행 명령과 성공 결과가 함께 보이게 한다.
- AWS 콘솔 캡처에는 리전, 리소스 이름, 상태가 보이게 한다.
- 각 단계 마지막의 **캡처 체크포인트**를 Notion 소제목으로 사용한다.

---

## 1. Local Kubernetes에 ingress-nginx 설치

### 1-1. Local Kubernetes 컨텍스트 확인

Docker Desktop 내장 Kubernetes를 사용할 경우:

1. Docker Desktop을 연다.
2. **Settings > Kubernetes**로 이동한다.
3. Kubernetes를 활성화하고 설정을 적용한다.
4. Kubernetes 상태가 Running이 될 때까지 기다린다.

```powershell
kubectl config get-contexts
kubectl config current-context
kubectl get nodes -o wide
```

현재 PC처럼 `minikube`가 이미 선택되어 있고 노드가 `Ready`라면 그대로 사용한다. Docker Desktop 내장 클러스터를 사용하려면 다음 명령으로 전환한다.

```powershell
kubectl config use-context docker-desktop
```

성공 기준: 현재 컨텍스트의 모든 노드 상태가 `Ready`.

### 1-2. ingress-nginx 설치 - CLI

현재 컨텍스트가 `minikube`이면 공식 addon을 사용한다.

```powershell
minikube addons enable ingress
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=300s

kubectl get all -n ingress-nginx
```

Pod가 계속 `Pending`이고 `kubectl describe pod -n ingress-nginx <POD_NAME>`의
Node-Selectors에 `minikube.k8s.io/primary=true`가 표시되면 노드 라벨을 확인한다.

```powershell
kubectl get node minikube --show-labels
kubectl label node minikube minikube.k8s.io/primary=true --overwrite
minikube addons enable ingress
kubectl rollout status deployment/ingress-nginx-controller `
  -n ingress-nginx `
  --timeout=300s
```

현재 컨텍스트가 `docker-desktop`이면 ingress-nginx 공식 Docker Desktop용 빠른 시작 manifest를 사용한다.

```powershell
$IngressVersion = "controller-v1.15.1"
$LocalIngressManifest = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$IngressVersion/deploy/static/provider/cloud/deploy.yaml"

kubectl apply -f $LocalIngressManifest
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=180s

kubectl get all -n ingress-nginx
```

### 1-3. 로컬 Ingress 동작 확인 - CLI

```powershell
kubectl create deployment ingress-demo --image=httpd:2.4 --port=80
kubectl expose deployment ingress-demo --port=80
kubectl create ingress demo-localhost `
  --class=nginx `
  --rule="demo.localdev.me/*=ingress-demo:80"

kubectl get deployment,service,ingress

$LocalIngressIp = if ((kubectl config current-context) -eq "minikube") {
  minikube ip
} else {
  "127.0.0.1"
}

curl.exe --resolve "demo.localdev.me:80:$LocalIngressIp" http://demo.localdev.me/
```

`It works!`가 출력되면 성공이다.

테스트 리소스를 정리한다.

```powershell
kubectl delete ingress demo-localhost
kubectl delete service ingress-demo
kubectl delete deployment ingress-demo
```

### 캡처 체크포인트

1. Docker Desktop Kubernetes Running 화면
2. `kubectl config current-context`와 `kubectl get nodes -o wide`의 Ready 상태
3. `kubectl get all -n ingress-nginx`
4. 브라우저 또는 `curl.exe`의 `It works!`

---

## 2. `petclinic:v1.0` Docker 이미지 생성 및 Registry Push

### 2-1. Dockerfile 준비 - CLI

프로젝트 루트에 포함된 `Dockerfile`은 아래와 같다.

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /workspace

COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -q -DskipTests dependency:go-offline

COPY src src
RUN ./mvnw -DskipTests package

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S petclinic && adduser -S petclinic -G petclinic
WORKDIR /app
COPY --from=build /workspace/target/spring-petclinic-*.jar app.jar
USER petclinic
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

권장 `.dockerignore`:

```text
.git
.github
.gradle
.idea
.mvn/wrapper/maven-wrapper.jar
build
target
docs
.env
.env.*
*.pem
*.key
```

### 2-2. 이미지 빌드와 로컬 실행 - CLI

```powershell
docker build -t petclinic:v1.0 .
docker image inspect petclinic:v1.0 `
  --format "ID={{.Id}} Size={{.Size}}"

docker run --rm -d `
  --name petclinic-local `
  -p 8080:8080 `
  petclinic:v1.0

docker logs petclinic-local
```

브라우저에서 `http://localhost:8080`에 접속한 뒤 정상 화면을 확인한다.

```powershell
docker stop petclinic-local
```

### 2-3. Docker Hub 저장소 생성 - 콘솔

1. Docker Hub에 로그인한다.
2. **My Hub > Repositories > Create repository**를 선택한다.
3. Repository name은 `petclinic`으로 입력한다.
4. 실습에서 EKS가 인증 없이 Docker Hub 이미지를 사용해야 한다면 Visibility를 **Public**으로 선택한다.
5. **Create**를 선택한다.

### 2-4. Docker Hub Push - CLI

현재 실습 계정의 Docker Hub ID는 `fdsien`이다. 다른 계정으로 실습할 때만 값을 바꾼다.

```powershell
$DockerHubId = "fdsien"

docker login --username $DockerHubId
docker tag petclinic:v1.0 "$DockerHubId/petclinic:v1.0"
docker push "$DockerHubId/petclinic:v1.0"
```

Docker Hub의 `petclinic` 저장소 **Tags** 화면에서 `v1.0`을 확인한다. 현재 Push된 이미지 주소는 다음과 같다.

```text
docker.io/fdsien/petclinic:v1.0
```

### 2-5. ECR Private Repository 생성 - AWS 콘솔

1. AWS 콘솔에서 **Elastic Container Registry > Private registry > Repositories**로 이동한다.
2. **Create repository**를 선택한다.
3. Visibility settings: **Private**
4. Repository name: `petclinic`
5. Tag immutability: 실습에서는 Mutable 사용 가능
6. Encryption: 기본 AES-256 사용 가능
7. **Create repository**를 선택한다.
8. 생성된 Repository URI를 기록한다.

### 2-6. ECR 로그인과 Push - Windows PowerShell

AWS CLI가 서울 리전을 사용하고 있는지 확인한다.

```powershell
$Region = "ap-northeast-2"
$AwsAccountId = aws sts get-caller-identity `
  --query Account `
  --output text
$EcrRegistry = "$AwsAccountId.dkr.ecr.$Region.amazonaws.com"
$EcrImage = "$EcrRegistry/petclinic:v1.0"

# Windows PowerShell 5.1의 네이티브 파이프 인코딩 문제를 피한다.
cmd.exe /d /s /c `
  "aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $EcrRegistry"

docker tag petclinic:v1.0 $EcrImage
docker push $EcrImage
Write-Output $EcrImage

aws ecr describe-images `
  --repository-name petclinic `
  --image-ids imageTag=v1.0 `
  --region $Region `
  --query "imageDetails[0].{Tags:imageTags,Digest:imageDigest,PushedAt:imagePushedAt}" `
  --output table `
  --no-cli-pager
```

마지막에 출력된 ECR 이미지 URI를 메모한다. 5단계 Deployment에서 사용한다.

AWS 콘솔의 ECR `petclinic` 저장소에서 태그 `v1.0`과 이미지 digest를 확인한다.

현재 Push된 ECR Private 이미지 주소는 다음과 같다.

```text
764643926176.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic:v1.0
```

두 Registry에 Push된 이미지의 digest는
`sha256:18ef12de89cb2c0ba2ef144ca1816d1c6385c44b72b8f2a9dc9c82e7cb2d2b78`이다.

### 캡처 체크포인트

1. `docker build` 성공 마지막 부분
2. `docker image inspect petclinic:v1.0`
3. 브라우저의 PetClinic 메인 화면
4. Docker Hub `petclinic:v1.0` Tags 화면
5. ECR Private Repository의 `v1.0` 이미지 화면

---

## 3. Bastion Host 구성

### 3-1. EC2 인스턴스 생성 - AWS 콘솔

AWS 콘솔에서 **EC2 > Instances > Launch instances**로 이동하고 다음과 같이 설정한다.

| 항목 | 값 |
|---|---|
| Name | `demo-eks-bastion` |
| AMI | Amazon Linux 2023 AMI, x86_64 |
| Instance type | `t3.micro` |
| Key pair | 새 키 페어 생성, RSA, `.pem` |
| VPC | 기본 VPC |
| Subnet | 기본 VPC의 Public subnet |
| Auto-assign public IP | Enable |
| Security group name | `demo-eks-bastion-sg` |
| Inbound rule | SSH, TCP 22, Source `My IP` |

보안 그룹의 SSH Source는 `0.0.0.0/0`이 아니라 반드시 **My IP**를 선택한다.

인스턴스를 시작하고 상태가 `Running`, Status check가 `2/2 checks passed`가 될 때까지 기다린다.

> AWS 콘솔의 **My IP**는 생성 시점의 공인 IP를 `/32`로 등록한다. 이후 카페,
> 테더링, VPN 등으로 네트워크가 바뀌어 SSH가 실패하면 보안 그룹의 SSH Source를
> 현재 공인 IP `/32`로 갱신한다.

### 3-2. 원격 접속 - Windows PowerShell

EC2 인스턴스 상세 화면에서 Public IPv4 DNS 또는 Public IPv4 address를 복사한다.

```powershell
ssh -i "C:\PATH\demo-eks-bastion.pem" ec2-user@PUBLIC_DNS
```

Amazon Linux의 기본 사용자는 `ec2-user`이다.

### 3-3. AWS CLI 설치 또는 확인 - Bastion Bash

Amazon Linux 2023에 AWS CLI가 이미 있으면 버전만 확인한다.

```bash
aws --version
```

명령이 없다면 공식 AWS CLI v2 설치 파일을 사용한다.

```bash
sudo dnf install -y unzip curl tar gzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
aws --version
```

EC2 IAM Role을 연결한 경우 자격 증명을 파일에 저장하지 않아도 된다. 강의 계정에서 임시 Access Key를 제공한 경우에만 `aws configure`를 사용하고, 키 값은 캡처하지 않는다.

```bash
aws sts get-caller-identity
aws configure get region
```

`eksctl create cluster`를 실행하는 IAM 주체에는 EKS뿐 아니라
CloudFormation, EC2, Auto Scaling, IAM, Systems Manager 관련 생성 권한이 필요하다.
강의용 IAM 사용자 또는 Bastion의 IAM Role에 해당 권한이 있는지 먼저 확인한다.

기본 리전이 다르면 다음을 실행한다.

```bash
aws configure set region ap-northeast-2
```

### 3-4. kubectl 설치 - Bastion Bash

이 런북은 현재 AWS 공식 EKS 문서에 게시된 Kubernetes `1.35`용 Linux x86_64 바이너리를 사용한다.

```bash
curl -Lo kubectl \
  https://s3.us-west-2.amazonaws.com/amazon-eks/1.35.3/2026-04-08/bin/linux/amd64/kubectl
curl -Lo kubectl.sha256 \
  https://s3.us-west-2.amazonaws.com/amazon-eks/1.35.3/2026-04-08/bin/linux/amd64/kubectl.sha256

echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
chmod +x kubectl
sudo install -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

### 3-5. eksctl 설치 - Bastion Bash

공식 GitHub 최신 릴리스와 checksum을 사용한다.

```bash
EKSC_ARCH=amd64
EKSC_PLATFORM="$(uname -s)_${EKSC_ARCH}"

curl -sLO \
  "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${EKSC_PLATFORM}.tar.gz"
curl -sL \
  "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" \
  | grep "${EKSC_PLATFORM}" \
  | sha256sum --check

tar -xzf "eksctl_${EKSC_PLATFORM}.tar.gz" -C /tmp
sudo install -m 0755 /tmp/eksctl /usr/local/bin/eksctl
eksctl version
```

`eksctl`은 AWS가 안내하는 공식 GitHub 최신 릴리스를 사용한다.

### 캡처 체크포인트

1. EC2 인스턴스 목록의 `demo-eks-bastion`, Running, `t3.micro`
2. 인스턴스 Networking 화면의 기본 VPC와 Public IP
3. 보안 그룹 인바운드 SSH Source가 본인 IP `/32`인 화면
4. `aws --version`, `kubectl version --client`, `eksctl version`
5. `aws sts get-caller-identity` 결과 - Account와 ARN만 보이게 캡처

---

## 4. eksctl로 EKS 구성

과제 지정값:

- Cluster: `demo-eks`
- Region: `ap-northeast-2`
- Managed node group: `demo-ng`
- Instance type: `t3.medium`
- Node volume: `20GB`

### 4-1. 클러스터 생성 - Bastion CLI

기본 `eksctl create cluster`는 EKS용 VPC와 CloudFormation 스택을 새로 만든다.
Bastion은 과제 요구대로 기본 VPC에 두지만, EKS API의 기본 Public endpoint를 통해
클러스터를 관리할 수 있다. 따라서 이 실습에서는 Bastion과 EKS를 같은 VPC에
배치하기 위한 별도 피어링이 필요하지 않다.

```bash
eksctl create cluster \
  --name demo-eks \
  --region ap-northeast-2 \
  --version 1.35 \
  --managed \
  --nodegroup-name demo-ng \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --node-volume-size 20
```

생성에는 일반적으로 15~25분 정도 걸릴 수 있다. 명령을 중간에 종료하지 않는다.

### 4-2. 상태 확인 - CLI와 AWS 콘솔

```bash
aws eks update-kubeconfig \
  --name demo-eks \
  --region ap-northeast-2

eksctl get cluster --region ap-northeast-2
eksctl get nodegroup \
  --cluster demo-eks \
  --region ap-northeast-2

kubectl cluster-info
kubectl get nodes -o wide
```

AWS 콘솔에서 다음을 확인한다.

1. **EKS > Clusters > demo-eks** 상태가 Active
2. **Compute > Node groups > demo-ng** 상태가 Active
3. Node group의 instance type이 `t3.medium`
4. Node group의 Disk size가 `20 GiB`

### 캡처 체크포인트

1. `eksctl create cluster` 성공 마지막 부분
2. EKS 콘솔의 `demo-eks / Active`
3. `demo-ng / Active / t3.medium / 20 GiB`
4. `kubectl get nodes -o wide`에서 모든 노드가 Ready

---

## 5. Deployment로 `petclinic-app` Pod 3개 배포

### 5-1. ECR 이미지 URI 설정 - Bastion CLI

`YOUR_AWS_ACCOUNT_ID`를 2단계에서 확인한 값으로 바꾼다.

```bash
export AWS_ACCOUNT_ID="YOUR_AWS_ACCOUNT_ID"
export AWS_REGION="ap-northeast-2"
export ECR_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/petclinic:v1.0"

echo "${ECR_IMAGE}"
```

### 5-2. Deployment 생성 - CLI

```bash
kubectl create deployment petclinic-app \
  --image="${ECR_IMAGE}" \
  --replicas=3 \
  --port=8080

kubectl rollout status deployment/petclinic-app \
  --timeout=300s

kubectl get deployment petclinic-app
kubectl get pods \
  -l app=petclinic-app \
  -o wide
```

성공 기준:

- Deployment `READY`가 `3/3`
- Pod 3개가 모두 `Running`

Pod가 `ImagePullBackOff`이면 ECR URI, 리전, 이미지 태그와 노드 IAM Role의 ECR pull 권한을 확인한다.

```bash
kubectl describe pod \
  -l app=petclinic-app
```

### 캡처 체크포인트

1. `kubectl get deployment petclinic-app`의 `READY 3/3`
2. `kubectl get pods -l app=petclinic-app -o wide`의 Running Pod 3개

---

## 6. `petclinic-app`에 LoadBalancer 연결 및 DNS 접속

### 6-1. Service 생성 - CLI

```bash
kubectl expose deployment petclinic-app \
  --name petclinic-app \
  --type=LoadBalancer \
  --port=80 \
  --target-port=8080

kubectl get service petclinic-app --watch
```

`EXTERNAL-IP`가 `<pending>`에서 AWS DNS 이름으로 바뀌면 `Ctrl+C`로 watch를 종료한다.

```bash
export PETCLINIC_LB_DNS="$(
  kubectl get service petclinic-app \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
)"

echo "${PETCLINIC_LB_DNS}"
curl -I "http://${PETCLINIC_LB_DNS}"
```

### 6-2. AWS 콘솔과 브라우저 확인

1. AWS 콘솔에서 **EC2 > Load Balancers**로 이동한다.
2. Kubernetes가 만든 Load Balancer 상태가 Active인지 확인한다.
3. DNS name을 복사해 브라우저에서 `http://DNS_NAME`으로 접속한다.
4. PetClinic 화면이 표시되는지 확인한다.

### 캡처 체크포인트

1. `kubectl get service petclinic-app`의 Type `LoadBalancer`와 DNS
2. EC2 Load Balancers의 Active 상태와 DNS name
3. 브라우저 주소창에 AWS DNS와 PetClinic 화면

---

## 7. EKS에 ingress-nginx 설치

### 7-1. 기존 앱 LoadBalancer를 ClusterIP로 변경 - CLI

6단계 접속 캡처가 끝난 뒤 중복 Load Balancer 비용을 줄이기 위해 앱 Service를 ClusterIP로 변경한다.

```bash
kubectl patch service petclinic-app \
  -p '{"spec":{"type":"ClusterIP"}}'

kubectl get service petclinic-app
```

AWS 콘솔 **EC2 > Load Balancers**에서 6단계 Load Balancer가 삭제되는지 확인한다.

### 7-2. AWS용 ingress-nginx 설치 - CLI

현재 ingress-nginx 공식 문서의 AWS NLB manifest를 사용한다.

```bash
export INGRESS_VERSION="controller-v1.15.1"
export AWS_INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VERSION}/deploy/static/provider/aws/deploy.yaml"

kubectl apply -f "${AWS_INGRESS_MANIFEST}"

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

kubectl get all -n ingress-nginx
```

### 7-3. PetClinic Ingress 생성과 접속 - CLI

```bash
kubectl create ingress petclinic-ingress \
  --class=nginx \
  --rule="petclinic.local/*=petclinic-app:80"

kubectl get ingress petclinic-ingress

export INGRESS_DNS="$(
  kubectl get service ingress-nginx-controller \
    -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
)"

echo "${INGRESS_DNS}"
curl -I \
  -H "Host: petclinic.local" \
  "http://${INGRESS_DNS}/"
```

Ingress controller NLB가 생성되기까지 수 분이 걸릴 수 있다. `INGRESS_DNS`가 비어 있으면 아래 명령으로 기다린다.

```bash
kubectl get service ingress-nginx-controller \
  -n ingress-nginx \
  --watch
```

로컬 Windows의 hosts 파일을 변경하지 않고 브라우저로 확인하려면 PowerShell에서 다음을 사용할 수 있다.

```powershell
curl.exe -I `
  -H "Host: petclinic.local" `
  "http://INGRESS_DNS/"
```

### 캡처 체크포인트

1. `kubectl get all -n ingress-nginx`
2. `kubectl get ingress petclinic-ingress`
3. ingress-nginx-controller Service의 AWS DNS
4. `curl`의 HTTP 성공 응답
5. EC2 Load Balancers의 ingress-nginx NLB Active 화면

---

## 8. Deployment와 Service 삭제

Ingress를 먼저 삭제한 뒤 애플리케이션 리소스를 삭제한다.

```bash
kubectl delete ingress petclinic-ingress
kubectl delete deployment petclinic-app
kubectl delete service petclinic-app

kubectl get deployment petclinic-app
kubectl get service petclinic-app
kubectl get pods -l app=petclinic-app
```

마지막 세 명령에서 `NotFound` 또는 `No resources found`가 표시되면 성공이다.

### 캡처 체크포인트

1. `deployment.apps "petclinic-app" deleted`
2. `service "petclinic-app" deleted`
3. 삭제 후 `NotFound` 또는 `No resources found`

---

## 9. AWS 리소스 삭제

삭제 순서가 중요하다. Kubernetes LoadBalancer/Ingress를 먼저 삭제하지 않으면 AWS Load Balancer가 남을 수 있다.

### 9-1. ingress-nginx와 Load Balancer 삭제 - CLI

```bash
kubectl delete -f "${AWS_INGRESS_MANIFEST}"

kubectl get service --all-namespaces
kubectl get ingress --all-namespaces
```

`EXTERNAL-IP`가 있는 사용자 Service와 사용자 Ingress가 남아 있지 않은지 확인한다.

AWS 콘솔 **EC2 > Load Balancers**와 **Target Groups**에서 Kubernetes가 생성한 리소스가 삭제될 때까지 확인한다.

### 9-2. EKS 삭제 - 권장 CLI

`eksctl`로 생성한 CloudFormation 스택까지 함께 정리하기 위해 다음 명령을 권장한다.

```bash
eksctl delete cluster \
  --name demo-eks \
  --region ap-northeast-2 \
  --wait
```

성공 후 확인:

```bash
aws eks describe-cluster \
  --name demo-eks \
  --region ap-northeast-2
```

`ResourceNotFoundException`이면 삭제된 것이다.

### 9-3. EKS 콘솔 삭제 경로 - CLI 대신 콘솔을 사용할 경우

AWS 공식 삭제 순서를 따른다.

1. **EKS > Clusters > demo-eks > Compute**
2. Node group `demo-ng` 선택
3. **Delete** 선택 후 이름을 입력해 삭제
4. Node group 삭제 완료 후 Clusters 목록으로 이동
5. `demo-eks` 선택 후 **Delete**
6. **CloudFormation > Stacks**에서 `eksctl-demo-eks-...` 스택 확인
7. 남은 nodegroup 또는 cluster/VPC 스택이 있다면 의존 관계 순서대로 삭제

CLI 방식과 콘솔 방식을 섞어서 동시에 실행하지 않는다.

### 9-4. ECR 저장소 삭제 - AWS 콘솔

1. **ECR > Private registry > Repositories**
2. `petclinic` 선택
3. **Delete** 선택
4. 저장소 이름을 입력하고 강제 삭제를 확인

과제 검증을 위해 이미지를 보존해야 한다는 별도 지시가 있으면 제출 완료 후 삭제한다.

### 9-5. Bastion과 부속 리소스 삭제 - AWS 콘솔

1. **EC2 > Instances**에서 `demo-eks-bastion` 선택
2. **Instance state > Terminate instance**
3. 종료 완료 후 **Network & Security > Security Groups**
4. `demo-eks-bastion-sg` 선택 후 Delete
5. **Network & Security > Key Pairs**
6. 실습용 Key Pair 삭제
7. 로컬 PC의 `demo-eks-bastion.pem`도 안전하게 삭제

### 9-6. 잔여 비용 리소스 최종 점검 - AWS 콘솔

서울 리전에서 다음을 확인한다.

- EKS Clusters: `demo-eks` 없음
- EC2 Instances: Bastion과 EKS worker node 없음
- EC2 Load Balancers: 실습용 Load Balancer 없음
- EC2 Target Groups: 실습용 Target Group 없음
- ECR Repositories: 실습용 `petclinic` 없음
- CloudFormation Stacks: `eksctl-demo-eks-...` 스택 없음
- VPC: eksctl이 만든 실습용 VPC 없음
- NAT Gateways: 실습용 NAT Gateway 없음
- Elastic IPs: 실습용 미연결 EIP 없음
- Security Groups: `demo-eks-bastion-sg` 없음
- Key Pairs: 실습용 Key Pair 없음

### 캡처 체크포인트

1. ingress-nginx 삭제 명령 성공
2. `eksctl delete cluster` 완료 화면 또는 EKS 콘솔 삭제 화면
3. EKS Clusters 목록에서 `demo-eks`가 없는 화면
4. EC2 Load Balancers 목록에 실습용 LB가 없는 화면
5. EC2 Bastion이 Terminated인 화면
6. CloudFormation에 `eksctl-demo-eks` 활성 스택이 없는 화면

---

## 제출용 Notion/PDF 목차

1. 실습 개요와 환경
2. Local Kubernetes ingress-nginx
3. Docker 이미지 빌드
4. Docker Hub Push
5. ECR Push
6. Bastion Host
7. EKS `demo-eks`와 `demo-ng`
8. `petclinic-app` Pod 3개
9. LoadBalancer DNS 접속
10. ingress-nginx
11. Deployment/Service 삭제
12. AWS 리소스 정리
13. 트러블슈팅 및 회고

각 장은 다음 형식을 반복한다.

```text
목표
사용한 명령어 또는 AWS 콘솔 경로
실행 결과
캡처 이미지
성공 판정
발생한 오류와 해결 방법
```

PDF 내보내기 전 확인:

- 파일명: `1조_홍길동.pdf`
- 모든 명령어가 텍스트로 포함됨
- 각 단계의 성공 결과 캡처 포함
- Access Key, Secret Key, Token, `.env` 값이 보이지 않음
- LoadBalancer DNS 접속 화면 포함
- AWS 리소스 삭제 증빙 포함

---

## 공식 참고 문서

- [GitHub CLI - gh auth login](https://cli.github.com/manual/gh_auth_login)
- [GitHub CLI - gh repo create](https://cli.github.com/manual/gh_repo_create)
- [Docker Hub - Build and push your first image](https://docs.docker.com/get-started/introduction/build-and-push-first-image/)
- [Docker Hub - Push images to a repository](https://docs.docker.com/docker-hub/repos/manage/hub-images/push/)
- [Amazon ECR - Moving an image through its lifecycle](https://docs.aws.amazon.com/AmazonECR/latest/userguide/getting-started-cli.html)
- [Amazon ECR - Private registry authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)
- [Amazon EC2 - Instance launch parameters](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-launch-parameters.html)
- [Amazon EC2 - Connect with an SSH client](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-linux-inst-ssh.html)
- [AWS CLI v2 - Install or update](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Amazon EKS - Set up kubectl and eksctl](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)
- [eksctl - Installation options](https://docs.aws.amazon.com/eks/latest/eksctl/installation.html)
- [eksctl - Managed node groups](https://docs.aws.amazon.com/eks/latest/eksctl/nodegroup-managed.html)
- [eksctl - Cluster endpoint access](https://docs.aws.amazon.com/eks/latest/eksctl/vpc-cluster-access.html)
- [Kubernetes - Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [ingress-nginx - Installation guide](https://kubernetes.github.io/ingress-nginx/deploy/)
- [Amazon EKS - Delete a cluster](https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html)
