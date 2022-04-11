resource "aws_s3_bucket" "veto_crls" {
  bucket = "crl.${aws_route53_zone.cluster.name}"
}

resource "aws_s3_bucket_acl" "veto_crls" {
  bucket = aws_s3_bucket.veto_crls.id
  acl    = "public-read"
}