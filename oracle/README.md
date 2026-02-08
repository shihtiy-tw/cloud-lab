# Oracle Cloud Infrastructure (OCI)

🔜 **Coming Soon**

This directory will contain Oracle Cloud Infrastructure patterns and scenarios.

## Planned Services

### Compute
- **OKE** (Oracle Kubernetes Engine): Managed Kubernetes
- **Compute Instances**: Virtual machines
- **Container Instances**: Serverless containers
- **Functions**: Serverless functions

### Storage
- **Object Storage**: Scalable object storage
- **Block Volumes**: Block storage
- **File Storage**: Network file system
- **Archive Storage**: Long-term storage

### Database
- **Autonomous Database**: Self-driving database (ATP, ADW)
- **MySQL Database Service**: Managed MySQL with HeatWave
- **NoSQL Database**: Document and key-value storage
- **Database Cloud Service**: Traditional DB deployment

### Networking
- **VCN** (Virtual Cloud Network): Private networks
- **Load Balancer**: Network and application load balancing
- **DNS**: Managed DNS service
- **FastConnect**: Dedicated connectivity

### Security
- **IAM**: Identity and access management
- **Vault**: Key and secret management
- **Cloud Guard**: Security posture management
- **WAF**: Web application firewall

### Monitoring
- **Monitoring**: Metrics and alarms
- **Logging**: Log collection and analysis
- **Application Performance Monitoring**: APM service

## Structure

Will follow the same pattern as AWS:

```
oracle/
├── compute/
│   ├── oke/
│   ├── compute-instances/
│   └── functions/
├── storage/
│   ├── object-storage/
│   └── block-volumes/
├── database/
│   ├── autonomous-db/
│   ├── mysql/
│   └── nosql/
├── networking/
│   ├── vcn/
│   └── load-balancer/
├── security/
│   ├── iam/
│   └── vault/
└── monitoring/
    └── oci-monitoring/
```

## Contributing

If you'd like to contribute Oracle Cloud scenarios, please:
1. Follow the established cloud-lab structure
2. Include comprehensive documentation
3. Add Terraform modules and scenarios
4. Include integration tests
5. Follow OCI best practices
