# ADR 010: DNS-01 Validation via Cloudflare

## Context

Our K3s cluster currently serves HTTPS traffic with a self-signed certificate. We want to replace it with a trusted Let's Encrypt certificate for the lab environment.

Because the cluster runs on a local network and should not be exposed to the public internet, HTTP-01 is not a suitable option.

Initially, we used the domain `upwind.systems` (registered with Name.com). However, cert-manager does not provide a native DNS-01 solver for Name.com. Using it directly would require an additional webhook deployment.

We evaluated two approaches:
1. Run a community maintained Name.com webhook in the cluster.
2. Delegate DNS to Cloudflare (using the new domain `northlift.net`) and use cert-manager's native Cloudflare DNS-01 integration.

## Decision

We will use the domain **northlift.net** with DNS management delegated to Cloudflare. We will utilize cert-manager with the native Cloudflare DNS-01 solver.

We rejected the custom webhook approach because it adds extra components to the cluster and increases operational overhead. Cloudflare was chosen because it provides a more stable and simpler integration for DNS-01.

The Cloudflare API token is created with least-privilege permissions (Zone:DNS:Edit) and is stored as a Kubernetes Secret.

## Consequences

### Positive

* We can issue trusted Let's Encrypt certificates without exposing the cluster to the public internet.
* The setup uses cert-manager's Cloudflare DNS-01 integration, reducing bloat and maintenance.

### Negative

*  Adds a dependency on Cloudflare's API for certificate issuance and renewal.
