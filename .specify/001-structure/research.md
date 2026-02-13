# Research: Project Structure

## 1. Context
We need a monorepo structure that supports multiple cloud providers without causing dependency hell or naming conflicts.

## 2. Alternatives Considered

### Option A: Separate Repos for Each Cloud
- **Pros**: Clear separation, smaller repos.
- **Cons**: Harder to share patterns, fragmented governance.
- **Decision**: Rejected using Monorepo to align with "brainiverse" consolidation goals.

### Option B: Flat Structure (no category)
- **Pros**: Shallower hierarchy (`aws/ecs` instead of `aws/compute/ecs`).
- **Cons**: Cluttered root for providers with many services.
- **Decision**: Rejected. Categories (`compute`, `storage`) provide better navigation.

## 3. Best Practices
- **HashiCorp Standard**: Recommends separating modules from live infrastructure. We follow this by putting reusable code in `shared/modules`.
- **Terragrunt Style**: Often uses `live/` vs `modules/`. We use `scenarios/` to represent live examples and `infrastructure/` for local dev/testing of the module logic itself.
