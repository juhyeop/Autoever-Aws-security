# ---------------------------------------------------------------------------
# 대시보드 앱 서버 — Flask SOAR/SIEM/NMS 대시보드
#
# 앱 코드 자체는 이 테라폼에 포함하지 않습니다(별도 저장소/zip).
# 여기서는 실행 환경만 준비하고, 배포는 팀이 git clone 또는 scp로 진행하세요.
# 이 인스턴스의 IAM 역할에는 "읽기 전용 + ASR-* 실행 전용" 권한만 붙어 있습니다.
# ---------------------------------------------------------------------------
dnf install -y python3 python3-pip git

useradd -r -m -d /opt/dashboard -s /sbin/nologin dashboard || true
mkdir -p /opt/dashboard/app
chown -R dashboard:dashboard /opt/dashboard

python3 -m venv /opt/dashboard/venv
/opt/dashboard/venv/bin/pip install --upgrade pip
/opt/dashboard/venv/bin/pip install flask flask-sqlalchemy flask-login boto3 apscheduler openpyxl

# 앱을 올린 뒤 systemctl enable --now dashboard 하면 되도록 유닛만 미리 만들어 둡니다.
cat >/etc/systemd/system/dashboard.service <<'UNIT'
[Unit]
Description=SOAR/SIEM/NMS Security Dashboard (Flask)
After=network-online.target

[Service]
User=dashboard
WorkingDirectory=/opt/dashboard/app
Environment="DEMO_MODE=false"
Environment="AWS_REGION=${region}"
Environment="CPU_THRESHOLD=${cpu_threshold}"
Environment="MEM_THRESHOLD=${mem_threshold}"
ExecStart=/opt/dashboard/venv/bin/python run.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload

cat >/etc/motd <<'MOTD'
대시보드 앱 서버입니다.
  1) /opt/dashboard/app 에 Flask 앱을 배포하세요 (run.py 가 진입점).
  2) systemctl enable --now dashboard
  3) http://<이 인스턴스>:5000 (admin_cidr 에서만 접근 가능)
DEMO_MODE=false 이므로 실제 Security Hub / CloudWatch 를 조회합니다.
MOTD
