# AWS 기반 SOAR / SIEM / NMS 보안 관제 — Terraform

설계문서 `claude/soar-siem-nms-dashboard-architecture.md` (v7) 을 코드로 옮긴 것입니다.
아키텍처 다이어그램의 ①②③ 구역이 그대로 4개 모듈에 대응합니다.

| 모듈 | 다이어그램 위치 | 만드는 것 |
|---|---|---|
| `modules/network` | ① 보호 대상 인프라 | VPC, 3개 서브넷(Public-Web / Private-DB / Private-App), 라우팅, NAT(옵션), Security Group, NACL, VPC Flow Logs |
| `modules/compute` | ① 보호 대상 인프라 | EC2 5대(DVWA / MySQL 수동·자동 / Docker / 대시보드), IAM 역할 3종, Secrets Manager, ALB+WAF(옵션) |
| `modules/security` | ② 탐지 · 수집 (SIEM) | GuardDuty, Inspector(v2), AWS Config + 규칙 4개, IAM Access Analyzer, Security Hub, CloudTrail(+KMS, S3) |
| `modules/soar` | ③ 자동조치 · 대시보드 | EventBridge 규칙 3개, Lambda 2개, SSM Automation 플레이북, DynamoDB, SNS, CloudWatch 알람/대시보드 |

---

## 1. 사전 준비

```bash
terraform -version     # 1.6 이상
aws sts get-caller-identity   # 팀 계정으로 로그인됐는지 확인
curl -s ifconfig.me           # 본인 공인 IP (admin_cidr 에 넣을 값)
```

필요한 IAM 권한: EC2 / VPC / IAM / Lambda / SSM / Config / GuardDuty / Inspector /
Security Hub / CloudTrail / S3 / KMS / SNS / DynamoDB / EventBridge 생성 권한.
학습용 계정이면 보통 `AdministratorAccess` 로 진행합니다.

## 2. 배포

### 2-1. state 저장소 만들기 (한 번만)

```bash
cd bootstrap
terraform init
terraform apply
# 출력된 state_bucket_name / lock_table_name 을 메모
cd ..
```

그 다음 `backend.tf` 의 주석을 풀고 위 값을 채운 뒤:

```bash
terraform init -migrate-state
```

혼자 테스트할 때는 이 단계를 건너뛰고 로컬 state로 써도 됩니다.

### 2-2. 변수 채우기

```bash
cp terraform.tfvars.example terraform.tfvars
# admin_cidr 를 본인 공인 IP/32 로 반드시 수정
```

`terraform.tfvars` 는 `.gitignore` 에 있습니다. 공인 IP가 들어가니 커밋하지 마세요.

### 2-3. 최초 apply — NAT를 잠깐 켜는 이유

Private 서브넷 인스턴스는 부트스트랩 때 인터넷이 필요합니다
(패키지 설치, Secrets Manager 조회). 그래서 **최초 1회만** NAT를 켭니다.

```bash
terraform apply -var="enable_nat_gateway=true"

# 인스턴스 부트스트랩이 끝날 때까지 5~10분 대기
# (SSM Session Manager로 접속해 /var/log/cloud-init-output.log 확인 가능)

terraform apply          # enable_nat_gateway=false 로 되돌아감 → 시간당 과금 중단
```

NAT를 한 시간 켜는 비용은 $0.05 내외입니다. 계속 켜두면 월 $35 정도입니다.

## 3. 비용 통제

기본값은 **비싼 리소스를 전부 꺼둔 상태**입니다.

| 변수 | 기본값 | 켤 때 비용 |
|---|---|---|
| `enable_nat_gateway` | `false` | 시간당 + 데이터 처리 (월 $35 내외) |
| `enable_alb` | `false` | 시간당 (월 $20 내외) |
| `enable_waf` | `false` | WebACL 월 $5 + 룰그룹 + 요청당 |
| `enable_guardduty` | `true` | 30일 무료 후 분석량 기준 |
| `enable_inspector` | `true` | 15일 무료 후 스캔 대상 수 기준 |
| `enable_config` | `true` | 기록 항목당 — 아래 참고 |
| `enable_security_hub` | `true` | 30일 무료 후 점검 항목당 |
| `enable_access_analyzer` | `true` | 외부 접근 분석기는 **무료** |

AWS Config는 `all_supported = false` 로 두고 시나리오에 필요한 7개 리소스 타입만
기록하도록 좁혀놨습니다. 계정 전체를 기록하면 금방 비싸집니다.

`terraform output cost_warning` 으로 지금 켜진 유료 리소스를 확인할 수 있습니다.

## 4. 침해사례 시연

### 4-1. 자동 조치 (MySQL-자동) — 이 프로젝트의 핵심 데모

```bash
./demo/trigger-auto-remediation.sh
```

스크립트가 하는 일:

1. MySQL-자동 인스턴스의 SG에 `3306/0.0.0.0/0` 규칙 추가 (침해사례 재현)
2. 조치 전 인바운드 규칙 출력
3. `asr_trigger` Lambda 직접 호출
4. 조치 후 인바운드 규칙 출력 → **비어 있어야 정상**

실제 파이프라인(Config → Security Hub → EventBridge → Lambda → SSM)을 끝까지
보고 싶으면 `--wait` 를 주세요. 다만 Config 평가와 Security Hub 수집에
**5~15분**이 걸려서 발표 중에 쓰기엔 느립니다. 리허설 때 `--wait` 로 한 번
확인해두고, 발표 때는 지름길(Lambda 직접 호출)을 쓰는 걸 권합니다.

### 4-2. 수동 대응 대조군 (MySQL-수동)

```bash
./demo/trigger-auto-remediation.sh --manual
```

똑같이 3306을 열지만, 이 SG에는 `AutoRemediation=enabled` 태그가 없어서
**자동조치가 실행되지 않고 SNS로 "수동 확인 필요" 알림만** 갑니다.

DB를 2대 두는 설계가 코드로 구현된 지점이 바로 이 태그입니다
(`modules/soar/functions/asr_trigger/index.py` 의 `has_required_tag`).

### 4-3. 나머지 시나리오

| 대상 | 명령 | 어디서 보이나 |
|---|---|---|
| Web (DVWA) | ZAP/Nikto 스캔, SQLMap | WAF 카운터(켠 경우), Security Hub |
| MySQL 수동 | `hydra -l root -P pass.txt <IP> mysql` | CloudWatch Logs `/…/mysql/error`, GuardDuty |
| Docker | 인스턴스 접속 후 `scan-images.sh` | Trivy 출력, Inspector finding |
| AWS 계정 | 테스트 액세스 키를 다른 리전에서 호출 | CloudTrail, GuardDuty |

라이브 공격이 불안할 때를 대비해 GuardDuty 샘플 finding도 준비해두세요:

```bash
aws guardduty create-sample-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text) \
  --finding-types "UnauthorizedAccess:EC2/SSHBruteForce"
```

### 4-4. CPU/Mem 알람 (NMS)

```bash
# 아무 인스턴스에 SSM으로 접속해서
stress-ng --cpu 2 --timeout 400s     # 없으면: dnf install -y stress-ng
```

5분 연속 80%를 넘으면 SNS → 이메일로 알림이 옵니다.
`terraform output cloudwatch_dashboard_url` 로 지표 그래프도 볼 수 있습니다.

## 5. 대시보드 앱 연결

Flask 대시보드(별도 저장소)를 붙일 때 필요한 값들:

```bash
terraform output automation_document_name    # app/config.py 의 ALLOWED_AUTOMATION_DOCUMENTS
terraform output correlated_findings_table   # 상관분석 결과 DynamoDB 테이블
terraform output dashboard_private_ip
```

대시보드 EC2에는 이미 **읽기 전용 + `ASR-*` 실행 전용** IAM 역할이 붙어 있으므로
액세스 키를 따로 넣을 필요가 없습니다. `.env` 에 `DEMO_MODE=false` 만 두면 됩니다.

Private 서브넷에 있어서 브라우저로 바로 못 여니 SSM 포트포워딩을 쓰세요:

```bash
aws ssm start-session --target $(terraform output -json instance_ids | jq -r .dashboard) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5000"],"localPortNumber":["5000"]}'
# 이제 http://localhost:5000
```

## 6. 정리 (중요)

```bash
terraform destroy
```

`destroy` 로 안 지워지는 것들 — 시연이 끝나면 직접 확인하세요:

- **Security Hub / GuardDuty / Inspector / Config**: `enable_*` 를 `false` 로 두고
  apply 하면 비활성화됩니다. destroy만 하면 계정 설정이 남을 수 있습니다.
- **bootstrap/ 의 state 버킷과 잠금 테이블**: `prevent_destroy = true` 로 보호됩니다.
  정말 지우려면 그 줄을 먼저 지우세요.
- **CloudWatch Logs**: 보관 기간 14일로 설정해둬서 자동 삭제되지만, 즉시 지우려면 콘솔에서.
- **SG 규칙**: 시연 중 수동으로 연 규칙이 남아 있는지 확인.

## 7. 알려진 제약 · 주의사항

- **`terraform validate` 를 돌려보지 못했습니다.** 이 코드를 만든 환경에서
  Terraform 레지스트리 접근이 막혀 있어 provider 스키마 검증을 못 했습니다.
  대신 provider 6.x 공식 문서로 리소스/인자 이름을 하나씩 확인했고,
  HCL 파싱·상호참조·templatefile 변수·Lambda/SSM 파이썬 문법은 정적으로 검사했습니다.
  **팀에서 첫 `terraform init && terraform validate && terraform plan` 은 꼭 돌려보세요.**
- DVWA는 의도적으로 취약한 앱입니다. `admin_cidr` 로만 열리게 해뒀지만
  시연이 끝나면 인스턴스를 반드시 종료하세요.
- MySQL은 설계문서대로 RDS가 아니라 EC2에 설치합니다. RDS는 OS 레벨 접근이 막혀
  Hydra 무차별 대입의 인증 실패 로그를 수집할 수 없기 때문입니다.
- 자동조치 화이트리스트는 `asr_trigger/index.py` 의 `AUTO_REMEDIABLE_PATTERNS` 에
  있습니다. 팀이 합의한 기준으로 다듬어 쓰세요.
- Security Hub의 기본 표준(FSBP/CIS)은 `enable_default_standards = true` 로
  자동 활성화됩니다. 별도 `standards_subscription` 을 추가하면 충돌합니다.

## 8. 디렉토리 구조

```
.
├── versions.tf  providers.tf  variables.tf  main.tf  outputs.tf  backend.tf
├── terraform.tfvars.example
├── bootstrap/                    state용 S3 + DynamoDB (별도 apply)
├── demo/
│   └── trigger-auto-remediation.sh
└── modules/
    ├── network/                  VPC · 서브넷 · SG · NACL · Flow Logs
    ├── compute/                  EC2 5대 · IAM · Secrets · ALB/WAF
    │   └── userdata/             부트스트랩 스크립트 5종
    ├── security/                 GuardDuty · Inspector · Config · Security Hub · CloudTrail
    └── soar/                     EventBridge · Lambda · SSM Automation · SNS · 알람
        └── functions/
            ├── correlator/       GuardDuty × Inspector 상관분석
            └── asr_trigger/      자동조치 판단 · 실행요청
```
