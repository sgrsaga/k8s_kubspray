bucket       = "k8s-kubespray-tfstate" # globally-unique S3 bucket, must exist beforehand
key          = "clusters/aws/dev-ap-southeast-1/terraform.tfstate"
region       = "ap-south-1"
use_lockfile = true
encrypt      = true
