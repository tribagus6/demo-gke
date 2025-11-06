#!/bin/bash
set -e

echo "Creating GKE cluster"
gcloud beta container --project "orca-lab01" clusters create "cluster-gke-simpfullstack" --zone "asia-southeast2-c" --no-enable-basic-auth --cluster-version "1.33.5-gke.1162000" --release-channel "regular" --machine-type "e2-standard-2" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "60" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/cloud-platform" --num-nodes "1" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM,STORAGE,POD,DEPLOYMENT,STATEFULSET,DAEMONSET,HPA,JOBSET,CADVISOR,KUBELET,DCGM --enable-private-nodes --enable-master-global-access --enable-ip-alias --network "projects/orca-lab01/global/networks/gke-vpc" --subnetwork "projects/orca-lab01/regions/asia-southeast2/subnetworks/gke-subnet" --cluster-secondary-range-name "pod" --services-secondary-range-name "svc" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --enable-dns-access --enable-k8s-tokens-via-dns --enable-k8s-certs-via-dns --enable-ip-access --security-posture=standard --workload-vulnerability-scanning=disabled --enable-dataplane-v2 --enable-google-cloud-access --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --binauthz-evaluation-mode=DISABLED --enable-managed-prometheus --workload-pool "orca-lab01.svc.id.goog" --enable-shielded-nodes --shielded-integrity-monitoring --no-shielded-secure-boot --node-locations "asia-southeast2-c"

echo "Getting GKE Credentials"
gcloud container clusters get-credentials cluster-gke-simpfullstack --zone=asia-southeast2-c

echo "Creating Cloud SQL Instance"
gcloud sql instances create tasks-db \
  --database-version=POSTGRES_14 \
  --tier=db-f1-micro \
  --region=asia-southeast2

echo "Creating Cloud SQL User"
gcloud sql databases create tasks_db --instance=tasks-db
gcloud sql users set-password postgres \
  --instance=tasks-db \
  --password="1niPa55word"

echo "Getting Cloud SQL Connection Name"
gcloud sql instances describe tasks-db --format="value(connectionName)"
# orca-lab01:asia-southeast2:tasks-db

echo "Creating Artifact Registry"
gcloud artifacts repositories create fullstack-repo \
  --repository-format=docker \
  --location=asia-southeast2 \
  --description="Docker images for full stack app"

echo "Set Docker auth to Artifact Registry"
gcloud auth configure-docker asia-southeast2-docker.pkg.dev



docker build -t asia-southeast2-docker.pkg.dev/orca-lab01/fullstack-repo/backend:v1.5 ./backend
docker push asia-southeast2-docker.pkg.dev/orca-lab01/fullstack-repo/backend:v1.5

docker build -t asia-southeast2-docker.pkg.dev/orca-lab01/fullstack-repo/frontend:v1.5 ./frontend
docker push asia-southeast2-docker.pkg.dev/orca-lab01/fullstack-repo/frontend:v1.5

echo "Create GKE Service Account for SQL Proxy impersonation"
gcloud iam service-accounts create gke-sql-access \
  --display-name="GKE Cloud SQL Access"

echo "Binding cloudsql.client role to GKE Service account "
gcloud projects add-iam-policy-binding orca-lab01 \
  --member="serviceAccount:gke-sql-access@orca-lab01.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

echo "Creting KSA for backend service account"
kubectl create serviceaccount backend-sa

echo "Binding workloadidentityuser role to backend K8s service account"
gcloud iam service-accounts add-iam-policy-binding gke-sql-access@orca-lab01.iam.gserviceaccount.com \
  --member="serviceAccount:orca-lab01.svc.id.goog[default/backend-sa]" \
  --role="roles/iam.workloadIdentityUser"


kubectl annotate serviceaccount backend-sa \
  iam.gke.io/gcp-service-account=gke-sql-access@orca-lab01.iam.gserviceaccount.com

kubectl create secret generic backend-env \
  --from-literal=DB_USER=postgres \
  --from-literal=DB_PASSWORD=1niPa55word \
  --from-literal=DB_NAME=tasks_db

kubectl create configmap backend-config \
  --from-literal=INSTANCE_CONNECTION_NAME=orca-lab01:asia-southeast2:tasks-db

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

