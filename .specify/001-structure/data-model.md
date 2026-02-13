# Data Model: Project Structure

## 1. Directory Schema

The project structure is the primary data model for this spec. It enforces a strict hierarchy:

```
cloud-lab/
├── {provider}/          # enum: [aws, gcp, azure, oracle]
│   ├── {category}/      # enum: [compute, storage, database, networking, security, monitoring]
│   │   └── {service}/   # string: kebab-case
│   │       ├── infrastructure/
│   │       ├── scenarios/
│   │       └── tests/
│   └── ...
├── shared/
│   ├── modules/
│   └── patterns/
├── scripts/
└── .specify/
```

## 2. File Schema

Key files and their required locations:

| File | Location | Purpose |
|------|----------|---------|
| `main.tf` | `infrastructure/`, `scenarios/*/` | Terraform configuration |
| `README.md` | `{service}/`, `scenarios/*/` | Documentation |
| `*_test.go` | `tests/` | Terratest code |

## 3. Validation Rules

1. **Provider Validity**: Must vary from the allowed list.
2. **Category Validity**: Must be one of the standard categories.
3. **Naming Convention**: All directories must be `kebab-case`.
