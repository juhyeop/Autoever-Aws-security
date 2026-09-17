#!/bin/bash
# 모든 인스턴스 공통 부트스트랩: CloudWatch Agent 설치 + 메모리 지표 수집 시작.
# CPU는 EC2가 기본으로 올려주지만 메모리는 에이전트가 있어야 보입니다.
# (설계문서 NMS 파트 / 2-advanced.pdf Monitoring Hands-on 과 같은 구성)
set -euxo pipefail

dnf update -y
dnf install -y amazon-cloudwatch-agent

cat >/opt/aws/amazon-cloudwatch-agent/etc/cwagent-config.json <<'CWCONF'
{
  "agent": { "metrics_collection_interval": 60 },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": { "InstanceId": "$${aws:InstanceId}" },
    "aggregation_dimensions": [["InstanceId"]],
    "metrics_collected": {
      "mem":  { "measurement": [{ "name": "mem_used_percent", "rename": "mem_used_percent" }] },
      "disk": {
        "measurement": [{ "name": "used_percent", "rename": "disk_used_percent" }],
        "resources": ["/"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/secure",
            "log_group_name": "${log_group_auth}",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
CWCONF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/cwagent-config.json
