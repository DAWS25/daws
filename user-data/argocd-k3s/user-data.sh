#!/usr/bin/env bash

set -e

# Log to both cloud-init output and a dedicated log file.
exec > >(tee -a /var/log/user-data-argocd-k3s.log) 2>&1

echo "[$(date -Iseconds)] Starting Argo CD + TLS bootstrap on Amazon Linux 2023"

# ===== Configuration (override via EC2 user-data env exports if needed) =====
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@example.com}"
ARGOCD_HOSTNAME="${ARGOCD_HOSTNAME:-}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.7.16}"
SECRETS_DIR="${SECRETS_DIR:-/opt/gitops-secrets}"

retry() {
	local attempts="$1"
	local sleep_seconds="$2"
	shift 2
	local n=1
	until "$@"; do
		if [[ "$n" -ge "$attempts" ]]; then
			echo "Command failed after ${attempts} attempts: $*"
			return 1
		fi
		echo "Attempt ${n}/${attempts} failed for: $*"
		n=$((n + 1))
		sleep "${sleep_seconds}"
	done
}

get_public_ipv4() {
	local token
	token="$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
		-H "X-aws-ec2-metadata-token-ttl-seconds: 21600")"
	curl -sS -H "X-aws-ec2-metadata-token: ${token}" \
		"http://169.254.169.254/latest/meta-data/public-ipv4"
}

write_secret_field() {
	local namespace="$1"
	local secret_name="$2"
	local field_name="$3"
	local output_file="$4"

	kubectl -n "${namespace}" get secret "${secret_name}" -o "jsonpath={.data.${field_name}}" \
		| base64 -d >"${output_file}"
	chmod 600 "${output_file}"
}

echo "Installing base dependencies"
retry 5 10 dnf makecache
retry 5 10 dnf install -y curl tar gzip jq ca-certificates
update-ca-trust

echo "Preparing secrets directory at ${SECRETS_DIR}"
install -d -m 700 "${SECRETS_DIR}"

echo "Installing k3s"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --disable traefik" sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH="$PATH:/usr/local/bin"

echo "Waiting for Kubernetes API"
retry 30 5 kubectl get nodes

echo "Installing Helm"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "Adding Helm repositories"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "Installing ingress-nginx"
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
	--namespace ingress-nginx \
	--set controller.publishService.enabled=true

echo "Installing cert-manager"
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install cert-manager jetstack/cert-manager \
	--namespace cert-manager \
	--set crds.enabled=true

echo "Waiting for ingress-nginx and cert-manager rollouts"
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=10m
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=10m
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=10m
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=10m

if [[ -z "${ARGOCD_HOSTNAME}" ]]; then
	PUBLIC_IP="$(get_public_ipv4)"
	# sslip.io maps dashed IPv4 hostnames back to the IP via wildcard DNS.
	ARGOCD_HOSTNAME="argocd.${PUBLIC_IP//./-}.sslip.io"
fi

echo "Using Argo CD hostname: ${ARGOCD_HOSTNAME}"
echo "Creating Let's Encrypt ClusterIssuer"
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
	name: letsencrypt-prod
spec:
	acme:
		email: ${LETSENCRYPT_EMAIL}
		server: https://acme-v02.api.letsencrypt.org/directory
		privateKeySecretRef:
			name: letsencrypt-prod-account-key
		solvers:
			- http01:
					ingress:
						class: nginx
EOF

echo "Installing Argo CD with TLS-enabled ingress"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd \
	--namespace argocd \
	--version "${ARGOCD_CHART_VERSION}" \
	--set configs.params."server\\.insecure"=true \
	--set server.ingress.enabled=true \
	--set server.ingress.ingressClassName=nginx \
	--set server.ingress.hostname="${ARGOCD_HOSTNAME}" \
	--set server.ingress.tls=true \
	--set server.ingress.tlsSecretName=argocd-server-tls \
	--set server.ingress.annotations."cert-manager\\.io/cluster-issuer"=letsencrypt-prod \
	--set server.ingress.annotations."nginx\\.ingress\\.kubernetes\\.io/ssl-redirect"="true"

echo "Waiting for Argo CD server rollout"
kubectl -n argocd rollout status deploy/argocd-server --timeout=10m

echo "Waiting for Argo CD TLS certificate and secret"
retry 30 10 kubectl -n argocd wait --for=condition=Ready certificate/argocd-server-tls --timeout=30s
retry 30 10 kubectl -n argocd get secret argocd-server-tls

echo "Persisting generated secrets to ${SECRETS_DIR}"
echo "${ARGOCD_HOSTNAME}" >"${SECRETS_DIR}/argocd-hostname.txt"
chmod 600 "${SECRETS_DIR}/argocd-hostname.txt"

write_secret_field argocd argocd-initial-admin-secret password "${SECRETS_DIR}/argocd-initial-admin-password.txt"
write_secret_field argocd argocd-server-tls tls.crt "${SECRETS_DIR}/argocd-server-tls.crt"
write_secret_field argocd argocd-server-tls tls.key "${SECRETS_DIR}/argocd-server-tls.key"

retry 30 10 kubectl -n cert-manager get secret letsencrypt-prod-account-key
if kubectl -n cert-manager get secret letsencrypt-prod-account-key -o jsonpath='{.data.tls\.key}' >/dev/null 2>&1; then
	write_secret_field cert-manager letsencrypt-prod-account-key tls.key "${SECRETS_DIR}/letsencrypt-prod-account.key"
fi

echo "Bootstrap complete"
echo "Argo CD URL: https://${ARGOCD_HOSTNAME}"
echo "Important: Security group must allow inbound TCP 80 and 443 for ACME HTTP-01 validation and HTTPS access."
echo "Secrets written to: ${SECRETS_DIR}"
echo "Initial admin password file: ${SECRETS_DIR}/argocd-initial-admin-password.txt"
