# 1) Provision infra (APIs, VPC, NAT, GKE, Cloud SQL, Artifact Registry, WI SA)

Use your one-shot script (the latest version you and I finalized):

```bash
bash setup_fullstack_gke.sh
```

This creates:

* Custom VPC + Subnet (+ secondary ranges)
* Cloud NAT + Router
* GKE (private nodes, WI enabled)
* Cloud SQL Postgres (`tasks-db`, DB `tasks_db`, user `postgres` with password)
* Artifact Registry (`fullstack-repo`)
* **Workload Identity** SA `gke-sql-access` with `roles/cloudsql.client` and WI binding for `default/backend-sa`

---

# 2) Build & push images (backend first)

```bash
# Backend
docker build -t $REGION-docker.pkg.dev/$PROJECT_ID/$ARTIFACT_REPO/backend:v1.5 ./backend
docker push $REGION-docker.pkg.dev/$PROJECT_ID/$ARTIFACT_REPO/backend:v1.5
```

> We’ll build the **frontend later** after we know the Ingress IP.

---

# 3) Create K8s Secret for DB connection (YAML)

```

Apply:

```bash
kubectl apply -f k8s/secret-backend-env.yaml
```

---

# 4) Create K8s ServiceAccount (Workload Identity)

Apply:

```bash
kubectl apply -f k8s/sa-backend.yaml
```

---

# 5) Deploy backend + Cloud SQL Auth Proxy

Apply & wait:

```bash
kubectl apply -f backend.yaml
kubectl rollout status deployment/backend
```

---

# 6) Deploy frontend Service/Deployment (temporary image OK)

Create `frontend.yaml` (we’ll update the image later):

Apply:

```bash
kubectl apply -f frontend.yaml
kubectl rollout status deployment/frontend
```

---

# 7) Install NGINX Ingress Controller (if not installed)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
kubectl -n ingress-nginx get pods
```

---

# 8) Create a **single** Ingress for both frontend + backend

Apply & get IP:

```bash
kubectl apply -f k8s/ingress.yaml
kubectl get ingress fullstack-ingress
# Note the EXTERNAL-IP, e.g. 34.101.70.153
```

---

# 9) **Initialize the database schema** (one-liner)

Create the `tasks` table from inside the backend pod via the proxy:

```bash
kubectl exec -it deploy/backend -- sh -c \
'apt-get update && apt-get install -y postgresql-client && psql -h 127.0.0.1 -U $DB_USER -d $DB_NAME -c "CREATE TABLE IF NOT EXISTS tasks (id SERIAL PRIMARY KEY, title VARCHAR(255));"'
```

Sanity check:

```bash
curl http://<INGRESS_IP>/api/tasks
# Expected: []  (empty JSON array)
```

---

# 10) Build & push **frontend** with the **Ingress IP baked in**

> Replace `<INGRESS_IP>` with the value you saw (e.g. `34.101.70.153`).

```bash
docker build \
  --build-arg VITE_API_URL="http://<INGRESS_IP>/api" \
  -t $REGION-docker.pkg.dev/$PROJECT_ID/$ARTIFACT_REPO/frontend:v3.1 \
  ./frontend

docker push $REGION-docker.pkg.dev/$PROJECT_ID/$ARTIFACT_REPO/frontend:v3.1
kubectl set image deployment/frontend frontend=$REGION-docker.pkg.dev/$PROJECT_ID/$ARTIFACT_REPO/frontend:v3.1
kubectl rollout status deployment/frontend
```

Verify the bundle contains the IP:

```bash
kubectl exec -it deploy/frontend -- sh -c 'grep -R "<INGRESS_IP>" -n /app/dist || true'
```

---

# 11) Test end-to-end

```bash
# Backend (ingress)
curl http://<INGRESS_IP>/api/tasks

# Frontend
# Open in the browser:
#   http://<INGRESS_IP>
# Add a task and refresh; it should persist (Cloud SQL)
```

