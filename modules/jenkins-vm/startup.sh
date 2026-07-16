#!/bin/bash
set -e

# Java install (Jenkins ke liye zaroori)
apt-get update
apt-get install -y fontconfig openjdk-17-jre gnupg curl

# Jenkins install
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  "https://pkg.jenkins.io/debian-stable binary/" | tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update
apt-get install -y jenkins

# Docker install (build steps ke liye)
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

# Jenkins user ko docker group me daalo (docker commands chalane ke liye)
usermod -aG docker jenkins

# gcloud CLI already Debian image me pre-installed hota hai GCP par,
# lekin agar na ho to:
if ! command -v gcloud &> /dev/null; then
  curl https://sdk.cloud.google.com | bash
fi

# kubectl install
apt-get install -y kubectl || (
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
)

# gke-gcloud-auth-plugin (kubectl ko GKE se auth karne ke liye zaroori)
apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin || \
  gcloud components install gke-gcloud-auth-plugin --quiet

systemctl enable jenkins
systemctl restart jenkins
systemctl restart docker
