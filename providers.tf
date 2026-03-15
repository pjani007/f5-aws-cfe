# You can pass the provider and the backup (.tfstate location) under this file 

provider "aws" {
  region = var.aws_region
}

## Currently I dont know where the tfstate is getting stored, so I am leaving it empty but ypu can ask customer and pass the tfstate to that location like s3, blob or any internal storage.