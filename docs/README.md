# docs/

Cross-cloud documentation. Provider-specific material lives in that provider's
own tree — `aws/docs/` holds the AWS architecture overview and the tagging and
Terraform style standards.

| Path | Contents |
|------|----------|
| `guides/` | How to work with something once it exists |
| `runbooks/` | What to do when something is broken |

## Current contents

| Document | Read it when |
|----------|--------------|
| [`runbooks/dev-vm-break-glass.md`](./runbooks/dev-vm-break-glass.md) | **Before** you are locked out of a dev VM. The brokered-access design means a broken broker is a total lockout, and most of the preparation only works while you still have access. |
| [`guides/dev-vm-git-access.md`](./guides/dev-vm-git-access.md) | You need to `git push` from a dev VM. There is no SSH agent forwarding through SSM/IAP/Bastion, so the usual habits do not work. |

This directory was empty until the dev-VM work; it is not yet a complete
reference. Specifications live in [`.specify/`](../.specify/), and per-service
documentation lives in each service's own `README.md`.
