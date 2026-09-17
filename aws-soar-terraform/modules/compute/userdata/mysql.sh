# ---------------------------------------------------------------------------
# MySQL (MariaDB) 서버 — ${db_role} 대응 시나리오용
#
# 설계문서 2장 참고: RDS 대신 EC2에 직접 설치합니다.
# RDS는 OS 레벨 접근이 막혀 있어서 Hydra 무차별 대입의 "인증 실패 로그"를
# CloudWatch Agent로 수집하는 시나리오를 만들 수 없기 때문입니다.
# ---------------------------------------------------------------------------
dnf install -y mariadb105-server jq
systemctl enable --now mariadb

# root 비밀번호는 Secrets Manager에서 가져옵니다(평문으로 박아두지 않기).
# NAT Gateway나 VPC 엔드포인트가 없으면 이 호출이 실패하므로,
# 최초 부트스트랩 때만 enable_nat_gateway=true 로 올려두세요.
DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" \
  --region "${region}" \
  --query SecretString --output text | jq -r .password)

if [ -n "$DB_PASS" ]; then
  mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE DATABASE IF NOT EXISTS appdb;
FLUSH PRIVILEGES;
SQL
fi

# 인증 실패 로그를 남기도록 general/error 로그 활성화.
# Hydra 시나리오에서 이 로그가 탐지 근거가 됩니다.
cat >/etc/my.cnf.d/audit.cnf <<'MYCNF'
[mariadb]
log_error = /var/log/mariadb/mariadb-error.log
log_warnings = 2
MYCNF

mkdir -p /var/log/mariadb
chown mysql:mysql /var/log/mariadb
systemctl restart mariadb

# MySQL 에러 로그도 CloudWatch로 올립니다.
cat >/opt/aws/amazon-cloudwatch-agent/etc/mysql-logs.json <<'MYLOG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/mariadb/mariadb-error.log",
            "log_group_name": "${log_group_mysql}",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
MYLOG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a append-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/mysql-logs.json
