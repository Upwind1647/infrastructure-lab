# Kubernetes & Deployment

## 1. Concepts over Tools
* **Pod:** The smallest deployable unit running our container. Ephemeral.
* **Deployment:** The manager that ensures our desired replica count is always running.
* **Service:** Provides an internal IP and DNS name to route traffic to the ephemeral Pods.
* **Ingress:** The front door (Traefik). Routes external HTTP/HTTPS traffic from outside the cluster to the internal Services.

## 2. Workload Manifests
We deploy our FastAPI application. Due to our Proxmox host's CPU and memory limits, resource requests and limits are strictly enforced in all manifests.
The application manifests are located in `deploy/k8s/status-api.yaml`.

## 3. Operations & Troubleshooting (kubectl)
To interact with the cluster we use the following commands:

* **Verify Pod Status:** `kubectl get pods -o wide`
* **Check Logs:** `kubectl logs <pod-name>`
* **Test Internal Networking:** `kubectl exec -it <pod-name> -- curl http://localhost:8000/health`
* **Local Port-Forwarding:** `kubectl port-forward svc/status-api-service 8080:80`
* **Verify Ingress:** `kubectl get ingress`
