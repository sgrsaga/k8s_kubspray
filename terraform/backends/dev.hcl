bucket       = "CHANGE_ME-tfstate" # globally-unique S3 bucket, must exist beforehand
key          = "envs/dev/terraform.tfstate"
region       = "ap-south-1"
use_lockfile = true
encrypt      = true
