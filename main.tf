data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.sh")}"

  vars {
    aws_region   = "${var.region}"
    bucket_name  = "${var.bucket_name}"
    duo_ikey     = "${var.duo_ikey}"
    duo_skey     = "${var.duo_skey}"
    duo_host_api = "${var.duo_host_api}"
    company_name = "${var.company_name}"
  }
}

resource "aws_eip" "eip" {
  count = "${var.bastion_instance_count}"
  vpc   = true

  tags = {
    Bastion = true
  }
}

# Get default security group
data "aws_security_group" "default" {
  vpc_id = "${var.vpc_id}"
  name   = "default"
}

data "aws_security_group" "world_to_bastion" {
  vpc_id = "${var.vpc_id}"
  name   = "world_to_bastion"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "${var.bucket_name}"
  acl    = "bucket-owner-full-control"

  tags = "${merge(var.tags)}"
}

resource "aws_iam_role" "bastion_host_role" {
  name = "bastion_host_role"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com"
        ]
      },
      "Action": [
        "sts:AssumeRole"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "bastion_host_role_policy" {
  name = "bastion_host_role_policy"
  role = "${aws_iam_role.bastion_host_role.id}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::tsr-production-bastion",
            "Condition": {
                "StringEquals": {
                    "s3:prefix": "private-keys/"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::tsr-production-bastion",
            "Condition": {
                "StringEquals": {
                    "s3:prefix": "public-keys/"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::tsr-production-bastion/logs/*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::tsr-production-bastion/public-keys/*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::tsr-production-bastion/private-keys/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAddresses",
                "ec2:AssociateAddress"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "bastion_host_profile" {
  role = "${aws_iam_role.bastion_host_role.name}"
  path = "/"
}

resource "aws_launch_configuration" "bastion_launch_configuration" {
  image_id                    = "${lookup(var.bastion_amis, var.region)}"
  instance_type               = "t2.nano"
  enable_monitoring           = true
  associate_public_ip_address = false
  iam_instance_profile        = "${aws_iam_instance_profile.bastion_host_profile.name}"
  key_name                    = "${var.bastion_host_key_pair}"

  security_groups = [
    "${data.aws_security_group.world_to_bastion.id}",
    "${data.aws_security_group.default.id}",
  ]

  user_data = "${data.template_file.user_data.rendered}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bastion_auto_scaling_group" {
  launch_configuration = "${aws_launch_configuration.bastion_launch_configuration.name}"
  max_size             = "${var.bastion_instance_count}"
  min_size             = "${var.bastion_instance_count}"
  desired_capacity     = "${var.bastion_instance_count}"

  vpc_zone_identifier = [
    "${var.auto_scaling_group_subnets}",
  ]

  lifecycle {
    create_before_destroy = true
  }
}
