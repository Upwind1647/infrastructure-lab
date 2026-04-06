# ADR 018: Cloudflare Infrastructure as Code

## Context

ADR 016 established Cloudflare Tunnel and Cloudflare Access for internal operator surfaces such as argocd.northlift.net.

That phase still left three manual steps when onboarding a new internal service:

1. Add ingress hostname in GitOps values.
2. Run cloudflared tunnel route dns manually.
3. Create Access application and policy in the Zero Trust dashboard.

This manual split creates operational risk:

1. Drift between cluster intent, Cloudflare DNS, and Access policy state.
2. Lockout risk if policy edits are made ad hoc and not peer-reviewed.
3. Non-repeatable recovery after incident or account migration.
4. No single Git history for tunnel routing and identity controls.

We evaluated the following options:

1. Continue with dashboard and CLI clickops.
2. Use the Cloudflare Kubernetes Operator for tunnel and Access automation.
3. Add a dedicated OpenTofu module for Cloudflare and apply via GitHub Actions.

## Decision

We adopt option 3 and add terraform/cloudflare as a first-class OpenTofu module.

This module manages:

1. Tunnel object lifecycle.
2. Tunnel DNS host routing for internal hostnames.
3. Access applications.
4. Access policies.

## Consequences

### Positive

1. Cloudflare tunnel and Access controls become auditable, reviewable, and reproducible.
2. Service onboarding is reduced to Git changes and CI apply.
3. Import-first approach prevents accidental replacement of existing tunnel and Access objects.
4. Remote state locking prevents concurrent apply corruption.

### Negative

1. Adds dependency on AWS backend availability for Cloudflare applies.
2. Requires OIDC role setup and least-privilege IAM maintenance.
3. Incorrect Access policy edits in code can still cause lockout if review is weak.
4. Team must maintain provider version compatibility across Cloudflare API changes.

## Status

Accepted and implemented in Phase 11.
