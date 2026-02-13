# Quickstart: Project Structure

## 1. Browsing the Lab

The lab is organized by **Cloud Provider** > **Category** > **Service**.

To find AWS ECS examples:
```bash
cd aws/compute/ecs
```

## 2. Adding a New Service

To add a new service (e.g., AWS Lambda), ensure you follow the structure:

1. Create directory: `mkdir -p aws/compute/lambda`
2. Add standard subdirectories:
   ```bash
   mkdir -p aws/compute/lambda/{infrastructure,scenarios,tests}
   ```
3. Add a README:
   ```bash
   echo "# AWS Lambda" > aws/compute/lambda/README.md
   ```

## 3. Automated Validation

Run the structure test (once implemented) to verify compliance:

```bash
# Future command
./scripts/cloud.test.sh --structure
```
