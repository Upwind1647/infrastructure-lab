# Kubernetes Port-Forwarding: Debugging

## Context
Our K3s cluster uses the Traefik Ingress Controller to securely route external HTTPS traffic to our public-facing services (like the Status API). However, internal infrastructure components like our Redis database must remain isolated and are not exposed via an Ingress route.

When operators need to debug these internal services, they must bypass the standard ingress layer safely without altering the network topology.

## Objective
Establish a secure, temporary tunnel from the local administrative machine directly to the isolated `redis-service` inside the K3s cluster using the Kubernetes API.

## Execution

### Step 1: Establish the Tunnel
We use the `kubectl port-forward` command to bind a local port on the administrative machine to the target port of the internal service. This connection is tunneled securely through the established Kubernetes API control plane.

Execute the following command in a dedicated terminal window:

```bash
kubectl port-forward svc/redis-service 6379:6379
```
### Step 2: Verify Connectivity
Open a secondary terminal window and attempt to communicate with the local port. We use `redis-cli` to ping the database.

```bash
redis-cli -h 127.0.0.1 -p 6379 ping
```
Expected Output:
```bash
PONG
```
## Conclusion
The drill demonstrates that administrators can securely interact with isolated internal workloads without compromising the cluster's network boundary or modifying existing firewall rules. The Kubernetes API server acts as a secure bastion for targeted debugging.
