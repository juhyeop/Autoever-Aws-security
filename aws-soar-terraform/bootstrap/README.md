# bootstrap — 원격 state 백엔드 (선택)

로컬 state 로 실습해도 되지만, 팀이 나눠서 apply/destroy 하려면
state 를 S3 에 두고 DynamoDB 로 잠급니다.

## 사용법

```
cd bootstrap
terraform init
terraform apply     # state 용 S3 버킷 + DynamoDB 잠금 테이블 생성
```

그다음 상위 폴더의 `backend.tf` 주석을 풀고 값을 채운 뒤:

```
cd ..
terraform init -migrate-state
```

state 백엔드가 필요 없으면 이 폴더는 무시하고 로컬 state 로 진행하세요.
