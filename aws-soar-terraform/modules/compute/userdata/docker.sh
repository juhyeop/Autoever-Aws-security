# ---------------------------------------------------------------------------
# Docker 호스트 — 침해사례 시나리오 "Docker" (Trivy 이미지 스캔 → CRITICAL CVE)
#
# 일부러 오래된 태그의 이미지를 받아둬서 Trivy / Inspector가 CVE를 찾을 거리를
# 만들어 둡니다. 시연이 끝나면 인스턴스와 함께 정리하세요.
# ---------------------------------------------------------------------------
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user

# Trivy 설치 (RPM 저장소)
cat >/etc/yum.repos.d/trivy.repo <<'TRIVYREPO'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
TRIVYREPO

dnf install -y trivy || echo "trivy 설치 실패 - 인터넷 경로(NAT/엔드포인트)를 확인하세요"

# 취약점이 확실히 나오는 구버전 이미지
docker pull nginx:1.14 || true

cat >/usr/local/bin/scan-images.sh <<'SCAN'
#!/bin/bash
# 로컬 이미지 전체를 Trivy로 스캔해서 CRITICAL/HIGH만 출력
for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>'); do
  echo "=== $img ==="
  trivy image --severity CRITICAL,HIGH --quiet "$img"
done
SCAN
chmod +x /usr/local/bin/scan-images.sh
