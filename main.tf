variable "github_token" {
  type        = string
  description = "GitHub OAuth Token for connecting to CodePipeline."
  default     = ""
}

variable "region" {
  type        = string
  description = "AWS Region for resources."
  default     = "us-west-2"
}

variable "app_name" {
  type        = string
  description = "Name of the application."
  default     = "my-app"
}

provider "aws" {
  region = var.region
}

# S3 bucket for CodePipeline artifacts
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "${var.app_name}-pipeline-artifacts"
  acl    = "private"
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "${var.app_name}-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipelineFullAccess"
}

# IAM Role for EC2 deployment
resource "aws_iam_role" "ec2_role" {
  name = "${var.app_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# CodePipeline definition
resource "aws_codepipeline" "app_pipeline" {
  name     = "${var.app_name}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        Owner      = ""  # Replace with your GitHub username
        Repo       = ""        # Replace with your repository name
        Branch     = ""                  # Branch to track
        OAuthToken = var.github_token        # Token passed securely
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy_to_EC2"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      input_artifacts = ["source_output"]
      configuration = {
        ApplicationName = aws_codedeploy_app.ec2_app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.ec2_deployment_group.name
      }
    }
  }
}

# CodeDeploy application
resource "aws_codedeploy_app" "ec2_app" {
  name = "${var.app_name}-ec2-app"
  compute_platform = "Server"
}

# EC2 instance to deploy the code
resource "aws_instance" "app_instance" {
  ami           = "ami-0c55b159cbfafe1f0" # Example Amazon Linux 2 AMI, change for your region
  instance_type = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "${var.app_name}-instance"
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.app_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# CodeDeploy deployment group for EC2
resource "aws_codedeploy_deployment_group" "ec2_deployment_group" {
  app_name              = aws_codedeploy_app.ec2_app.name
  deployment_group_name = "${var.app_name}-deployment-group"
  service_role_arn      = aws_iam_role.codepipeline_role.arn

  deployment_config_name = "CodeDeployDefault.AllAtOnce"

  ec2_tag_set {
    ec2_tag_filter {
      key   = "devopscloud"
      value = "${var.app_name}-instance"
      type  = "KEY_AND_VALUE"
    }
  }
}
