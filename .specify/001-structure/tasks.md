# Tasks for Spec 001: Project Structure

- [x] Create `.specify/specs` directory if not exists <!-- id: 1 -->
- [x] Verify root level directories <!-- id: 2 -->
    - [x] `aws/`
    - [x] `gcp/`
    - [x] `azure/`
    - [x] `oracle/`
    - [x] `shared/`
    - [x] `scripts/`
    - [x] `.opencode/`
    - [x] `.specify/`
- [x] Verify standard categories in each cloud provider <!-- id: 3 -->
    - [x] `compute/`
    - [x] `storage/`
    - [x] `database/`
    - [x] `networking/`
    - [x] `security/`
    - [x] `monitoring/`

## Verification notes

Verified 2026-08-18. All directories exist for all four providers.

Existence is not the same as content, though. Outside `aws/`, the category
directories hold only `.gitkeep` files — there is no Terraform in `gcp/`,
`azure/`, or `oracle/` yet. The root `shared/`, `tests/`, `docs/`, and
`examples/` directories are likewise empty. `scripts/` was empty until SPEC-002
was implemented.
