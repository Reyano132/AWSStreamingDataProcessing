terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-south-1"
}



resource "aws_s3_bucket" "mybucket" {
  bucket        = "my-tf-test-bucket132"
  force_destroy = true

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3_stream" {
  name        = "myKDFStream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.mybucket.arn

    prefix              = "data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/!{firehose:error-output-type}/"

    buffering_size     = 2
    buffering_interval = 60
  }
}

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}


resource "aws_iam_policy" "policy_s3" {
  name = "policy_s3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:*"]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::*",
      },
    ]
  })
}

resource "aws_iam_role" "firehose_role" {
  name                = "firehose_test_role"
  assume_role_policy  = data.aws_iam_policy_document.firehose_assume_role.json
  managed_policy_arns = [aws_iam_policy.policy_s3.arn]
}


data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "policy_kdf" {
  name = "policy-kdf"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["firehose:*"]
        Effect   = "Allow"
        Resource = "*",
      },
    ]
  })
}

resource "aws_iam_role" "ec2_role" {
  name                = "ec2_test_role"
  assume_role_policy  = data.aws_iam_policy_document.ec2_assume_role.json
  managed_policy_arns = [aws_iam_policy.policy_kdf.arn]
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE5VRxIGPNSUurPV1LsQ7ebuuLJ7hNILBynbDrFO2xXi rushichaudhari26@gmail.com"
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH traffic"
  ingress {
    description = "Connect to Internet"
    from_port   = 0
    to_port     = 65535
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Connect to Internet"
    from_port   = 0
    to_port     = 65535
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}


resource "aws_instance" "my_instance" {
  ami                    = "ami-0a0f1259dd1c90938"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  instance_type          = "t2.nano"

  user_data = <<-EOF
    #!/bin/bash
    mkdir /tmp/data
    chmod +777 /tmp/data
    mkdir /tmp/generator
    chmod +777 /tmp/generator
    echo yes | sudo yum install aws-kinesis-agent
    echo yes | sudo yum install python
    echo yes | sudo yum install pip
    cd /etc/aws-kinesis
    sudo rm agent.json
    wget https://raw.githubusercontent.com/Reyano132/AWSStreamingDataProcessing/main/agent.json
    chmod +777 agent.json
    sudo service aws-kinesis-agent start

    cd /tmp/generator
    wget https://raw.githubusercontent.com/Reyano132/AWSStreamingDataProcessing/main/dataGenerator.py
    pip install faker
    python dataGenerator.py
    echo "Done!!" > result.txt
    EOF


  tags = {
    Name = "test-spot2nano"
  }

}

resource "aws_glue_catalog_database" "mydatabase" {
  name = "mydatabase"
}

resource "aws_glue_crawler" "mycrawler" {
  database_name = aws_glue_catalog_database.mydatabase.name
  name          = "mycrawler"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.mybucket.bucket}/data/"
  }
}

data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "policy_glue" {
  name = "policy-kdf"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "glue:*",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListAllMyBuckets",
          "s3:GetBucketAcl",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeRouteTables",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcAttribute",
          "iam:ListRolePolicies",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "cloudwatch:PutMetricData"
        ]
        Effect   = "Allow"
        Resource = "*",
      },
      {
        Action = [
          "s3:CreateBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Effect   = "Allow"
        Resource = "*",
      },
      {
        Action = [
          "s3:GetObject"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::crawler-public*",
          "arn:aws:s3:::aws-glue-*"
        ],
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:logs:*:*:*:/aws-glue/*"
        ]
      },
      {
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:instance/*"
        ]
      }
    ]
  })
}


resource "aws_iam_role" "glue_role" {
  name                = "glue_test_role"
  assume_role_policy  = data.aws_iam_policy_document.glue_assume_role.json
  managed_policy_arns = [aws_iam_policy.policy_glue.arn]
}

