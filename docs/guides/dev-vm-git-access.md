# Pushing to git from the dev VM

**Applies to** `{aws,gcp,azure}/compute/dev-vm`

## The problem

Access to the dev VM is brokered — SSM Session Manager, IAP, or Bastion — and none
of those is an SSH client in the normal sense. So the two habits you would
normally reach for do not work:

- **No SSH agent forwarding.** There is no `ssh -A` in the chain, so your
  workstation's key is not available on the box.
- **No `~/.ssh/id_ed25519` to copy up.** Copying a private key onto a shared,
  auto-stopping lab VM is exactly the thing the brokered-access design exists to
  avoid, and the disk survives `terraform destroy`, so the key would outlive the
  VM you put it on.

The image installs `gh` (via the dotfiles' `make install`), which gives a clean
answer.

## Recommended: `gh auth login` device flow

The device flow needs no inbound connectivity and no key on disk. You authenticate
in a browser on your workstation; the box only ever holds a token.

```bash
gh auth login --hostname github.com --git-protocol https --web
# prints a one-time code, then:
#   ! First copy your one-time code: XXXX-XXXX
#   Press Enter to open github.com in your browser...
```

The box has no browser, so **do not press Enter expecting one to open** — copy the
URL it prints (`https://github.com/login/device`) and the code, and open them on
your workstation. Then:

```bash
gh auth setup-git          # makes git use gh as a credential helper over HTTPS
git -C ~/dotfiles remote -v # confirm the remote is https://, not git@
```

Existing clones with a `git@github.com:` remote will still try SSH. Switch them:

```bash
git remote set-url origin https://github.com/shihtiy-tw/dotfiles.git
```

### Scope it down

The token `gh` mints by default is broad. For a lab box, re-auth with only what
you need:

```bash
gh auth login --scopes 'repo,read:org' --web
```

`gh auth status` shows the current scopes. Note the token is stored in
`~/.config/gh/hosts.yml` — which lives on the **persistent data disk**, so it
survives a rebuild. That is convenient and also means revoking it is a real step
when you retire the box, not something the destroy handles for you.

## Alternative: a fine-grained PAT from the cloud's secret store

Preferable when you want the credential centrally revocable, or when several VMs
should share one identity. Each cloud can hand the token to the box using the
VM's own scoped identity, so nothing is typed in and nothing is baked into the
image:

```bash
# AWS
aws ssm get-parameter --name /dev-vm/github-token --with-decryption \
  --query Parameter.Value --output text

# GCP
gcloud secrets versions access latest --secret=dev-vm-github-token

# Azure
az keyvault secret show --vault-name "$KV" --name dev-vm-github-token \
  --query value -o tsv
```

Then:

```bash
gh auth login --with-token < <(...one of the above...)
```

If you take this path, the VM's identity needs read access to exactly that one
secret — not to the store. The scoped-identity design in
[`.specify/003-dev-vm/data-model.md`](../../.specify/003-dev-vm/data-model.md) §6
is the reason that is a one-line role addition rather than a rethink.

Use a **fine-grained** PAT with a short expiry, restricted to the specific
repositories. A classic `repo`-scoped PAT on a lab VM is a broad credential
sitting on a disk that outlives the machine.

## Not recommended, and why

| Approach | Why not |
|----------|---------|
| Copy your personal SSH key up | Long-lived credential on a disk that survives destroy, with no revocation story short of rotating the key everywhere. |
| SSH agent forwarding | Not available through any of the three brokers. |
| Deploy keys per repo | Fine for one repo, unmanageable at three clouds × several repos. |
| Committing a token to the dotfiles repo | `detect-secrets` and `git-secrets` run in this repo's pre-commit for exactly this reason. |

## Signing commits

If you sign commits, the same constraint applies — your signing key is not on the
box. `gh` can do SSH-key signing with a key generated *on* the VM and registered
as a signing key:

```bash
ssh-keygen -t ed25519 -C "dev-vm-$(hostname)" -f ~/.ssh/git-signing -N ''
gh ssh-key add ~/.ssh/git-signing.pub --type signing --title "dev-vm $(hostname)"
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/git-signing.pub
git config --global commit.gpgsign true
```

A per-VM signing key is the right shape here: it is revocable independently, and
losing the box costs one key rather than your identity.

## Status

Written with **no CSP credentials available**, so the secret-store commands are
from documentation and unexecuted. The `gh` device flow is the load-bearing
recommendation and is standard `gh` behaviour; verify the rest when the VM first
comes up.
