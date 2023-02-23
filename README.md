# terraform-infrastructure

Welcome to my Terraform multi-purpose repository! It contains well-structured AWS Terraform scripts for infrastructure provisioning, deployment, and management. Contributions from the community are welcome, feel free to submit a pull request. Simplify your infrastructure deployments with my scripts!

## Requirements

[Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) is required to be installed, it is recommended to use the latest version. To check the version, the following command is available:

```bash
terraform -v
```

The [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) is a nice to have too in case there is something Terraform cannot create.

## Usage

The standard Terraform commands can be used:

```bash
# Format the files
terraform fmt
# Validate the files
terraform validate
# Show the TF plan
terraform plan
# Apply the plan & create the resources
terraform apply
# Delete all resources
terraform destroy
```

## Permissions

To define which permissions a template might need, the [IAMLive](https://github.com/iann0036/iamlive) tool can be used. To use it, 2 terminal windows are required.

-   Window 1: Monitoring the IAM permissions. The following command can be used:
    ```bash
      iamlive --set-ini
    ```
-   Window 2: Runs the TF scripts. It needs first to run this command to enable monitoring:
    ```bash
      export AWS_CSM_ENABLED=true
    ```
