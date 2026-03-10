# K3s Architecture on Proxmox

## 1. Concepts over Tools
Standard Kubernetes (K8s) is designed for large-scale deployments. It relies on distributed databases (`etcd`) and multiple independent control-plane processes, which introduce high memory and CPU overhead.

Given our Proxmox host is a resource-constrained Ryzen 5 processor, we utilize **K3s**. K3s is a certified Kubernetes distribution built for IoT and Edge computing.

## 2. The K3s Efficiency Model
K3s achieves its lightweight footprint through several architectural choices:
* **Single Binary:** The API Server, Scheduler, and Controller Manager are packaged into a single binary and run as a single process.
* **Datastore:** It drops `etcd` by default in favor of an embedded SQLite database.
* **Container Runtime:** It natively embeds `containerd`, removing the need for a standalone Docker daemon.



## 3. Architecture Diagram

```mermaid
graph TD
    subgraph Proxmox Host ["Proxmox VE (Ryzen 5)"]
        subgraph K3s VM ["Debian 12 VM (2 Cores, 4GB RAM)"]

            subgraph K3s Server ["K3s Server Process (Control Plane)"]
                API["API Server"]
                Sched["Scheduler"]
                CM["Controller Manager"]
                SQLite[("SQLite<br>(State)")]

                API --- Sched
                API --- CM
                API --- SQLite
            end

            subgraph K3s Agent ["K3s Agent Process (Worker Node)"]
                Kubelet["Kubelet"]
                KubeProxy["Kube-Proxy"]
                Containerd["containerd<br>(Runtime)"]

                Kubelet --- KubeProxy
                Kubelet --- Containerd
            end

            API <==> Kubelet

            subgraph Pods ["Workloads"]
                App["Status API Pod"]
                Redis["Redis Pod"]
            end

            Containerd --> Pods
        end
    end
```
