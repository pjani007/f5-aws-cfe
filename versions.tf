terraform {
  required_version = ">= 1.3.0"     ### You can choose as per your desire version

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"             ### You can choose as per your desire version
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"                ### You can choose as per your desire version. ## you can go to terraform website and see the versioning of null provider
    }
  }
}