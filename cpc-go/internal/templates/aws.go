// Package templates contains the string templates for generating example
// deployment configurations.
package templates

// AWSDeployment is the template for an AWS deployment.yaml.
const AWSDeployment = `
apiVersion: cpc.abevz.dev/v1alpha1
kind: ClusterDeployment
metadata:
  name: aws-eks-example

tofuBackend:
  type: s3
  config:
    bucket: "your-tfstate-bucket-name"
    key: "aws-eks-example/terraform.tfstate"
    region: "eu-central-1"

spec:
  provider: aws
  provider_config:
    aws:
      region: "eu-central-1"

  instanceProfiles:
    - name: "eks-worker"
      resources:
        cpu: 2
        memory: "4Gi"
      providerSettings:
        aws:
          instanceType: "t3.medium"
          ami: "ami-0c55b159cbfafe1f0" # Amazon Linux 2 in eu-central-1, please verify the latest AMI ID

  nodeGroups:
    - name: "eks-workers"
      profile: "eks-worker"
      count: 2
`

// AWSSecrets is the template for an AWS secrets.sops.yaml.
const AWSSecrets = `
provider_credentials:
  aws:
    access_key: "YOUR_AWS_ACCESS_KEY_ID"
    secret_key: "YOUR_AWS_SECRET_ACCESS_KEY"
`
