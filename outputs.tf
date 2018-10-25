output "bucket_name" {
  value = "${aws_s3_bucket.bucket.bucket}"
}

output "aws_eip" {
  value = "${aws_eip.eip.*.public_ip}"
}
