output "bucket_name" {
  value = "${aws_s3_bucket.bucket.bucket}"
}

output "private_instances_security_group" {
  value = "${aws_security_group.private_instances_security_group.id}"
}
