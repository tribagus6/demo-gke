#!/bin/bash
set -e

PROJECT_ID="orca-lab01"
REGION="asia-southeast2"
ZONE="asia-southeast2-c"
VPC_NAME="gke-vpc"
SUBNET_NAME="gke-subnet"
ROUTER_NAME="gke-router"
NAT_NAME="gke-nat-gateway"
NAT_IP_NAME="gke-nat-ip"
ARTIFACT_REPO="fullstack-repo"
DB_INSTANCE="tasks-db"
DB_NAME="tasks_db"
DB_PASSWORD="1niPa55word"
CLUSTER_NAME="cluster-gke-simpfullstack"

echo "===================="
echo " ENABLE REQUIRED APIs"
echo "===================="
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  dns.googleapis.com \
  storage.googleapis.com

echo "===================="
echo " CREATE CUSTOM VPC + SUBNET"
echo "===================="
gcloud compute networks create $VPC_NAME \
  --project=$PROJECT_ID \
  --subnet-mode=custom

gcloud compute networks subnets create $SUBNET_NAME \
  --project=$PROJECT_ID \
  --network=$VPC_NAME \
  --region=$REGION \
  --range=192.168.0.0/24 \
  --secondary-range=pod=10.10.0.0/18,svc=10.10.64.0/18

echo "===================="
echo " CREATE CLOUD NAT"
echo "===================="
gcloud compute addresses create $NAT_IP_NAME \
  --project=$PROJECT_ID \
  --region=$REGION

gcloud compute routers create $ROUTER_NAME \
  --project=$PROJECT_ID \
  --network=$VPC_NAME \
  --region=$REGION

gcloud compute routers nats create $NAT_NAME \
  --project=$PROJECT_ID \
  --router=$ROUTER_NAME \
  --region=$REGION \
  --nat-external-ip-pool=$NAT_IP_NAME \
  --nat-custom-subnet-ip-ranges=$SUBNET_NAME

echo "===================="
echo " CREATE GKE CLUSTER"
echo "===================="
gcloud beta container --project $PROJECT_ID clusters create $CLUSTER_NAME \
  --zone "$ZONE" \
  --no-enable-basic-auth \
  --cluster-version "1.33.5-gke.1162000" \
  --release-channel "regular" \
  --machine-type "e2-standard-2" \
  --num-nodes "1" \
  --network "projects/$PROJECT_ID/global/networks/$VPC_NAME" \
  --subnetwork "projects/$PROJECT_ID/regions/$REGION/subnetworks/$SUBNET_NAME" \
  --cluster-secondary-range-name "pod" \
  --services-secondary-range-name "svc" \
  --enable-ip-alias \
  --enable-private-nodes \
  --enable-master-global-access \
  --enable-google-cloud-access \
  --enable-managed-prometheus \
  --workload-pool "$PROJECT_ID.svc.id.goog"

echo "===================="
echo " GET GKE CREDENTIALS"
echo "===================="
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE

echo "===================="
echo " CREATE CLOUD SQL (POSTGRES)"
echo "===================="
gcloud sql instances create $DB_INSTANCE \
  --database-version=POSTGRES_14 \
  --tier=db-f1-micro \
  --region=$REGION

gcloud sql databases create $DB_NAME --instance=$DB_INSTANCE

gcloud sql users set-password postgres \
  --instance=$DB_INSTANCE \
  --password=$DB_PASSWORD

echo "Cloud SQL Connection Name:"
gcloud sql instances describe $DB_INSTANCE --format="value(connectionName)"

echo "===================="
echo " CREATE ARTIFACT REGISTRY"
echo "===================="
gcloud artifacts repositories create $ARTIFACT_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Docker repo for fullstack app"

echo "===================="
echo " DOCKER AUTH TO ARTIFACT REGISTRY"
echo "===================="
gcloud auth configure-docker $REGION-docker.pkg.dev

echo "===================="
echo " CREATE GKE SERVICE ACCOUNT (Workload Identity)"
echo "===================="
gcloud iam service-accounts create gke-sql-access \
  --display-name="GKE Cloud SQL Access"

echo " Bind Cloud SQL Client role to SA"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:gke-sql-access@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

echo " Bind workloadIdentityUser to backend K8s SA (backend-sa)"
gcloud iam service-accounts add-iam-policy-binding gke-sql-access@$PROJECT_ID.iam.gserviceaccount.com \
  --member="serviceAccount:$PROJECT_ID.svc.id.goog[default/backend-sa]" \
  --role="roles/iam.workloadIdentityUser"

echo "✅ DONE — GKE + VPC + Cloud SQL + Workload Identity configured."
