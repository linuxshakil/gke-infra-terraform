cat > modules/jenkins-vm/startup.sh << 'EOF'
#!/bin/bash
set -e

# Network ready hone ka wait (boot ke turant baad kabhi kabhi DNS/network slow hota hai)
sleep 15

apt-get update
apt-get install -y fontconfig openjdk-17-jre gnupg curl

# Jenkins GPG key — dearmor karke binary keyring banao (apt ko yahi chahiye)
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg]" \
  "https://pkg.jenkins.io/debian-stable binary/" | tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update
apt-get install -y jenkins

# Docker install
apt-get install -y ca-certificates
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

usermod -aG docker jenkins

if ! command -v gcloud &> /dev/null; then
  curl https://sdk.cloud.google.com | bash
fi

if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
fi

apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin || true

systemctl enable jenkins
systemctl restart jenkins
systemctl restart docker
EOF