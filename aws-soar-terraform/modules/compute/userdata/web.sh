# ---------------------------------------------------------------------------
# 웹서버: DVWA (침해사례 시나리오 "Web Server" — ZAP/Nikto 스캔, SQLMap)
#
# 의도적으로 취약한 앱입니다. Security Group에서 팀 IP(admin_cidr)로만 열어두었고,
# 시연이 끝나면 인스턴스를 꼭 종료하세요.
# ---------------------------------------------------------------------------
dnf install -y docker
systemctl enable --now docker

# 재부팅해도 올라오도록 restart 정책을 줍니다.
docker run -d --name dvwa --restart unless-stopped -p 80:80 vulnerables/web-dvwa

echo "DVWA ready. 기본 계정 admin / password, 최초 접속 후 Create/Reset Database 클릭." \
  >/etc/motd
