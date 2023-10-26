resource "aws_kms_key" "gateway_jwt_signing_key" {
  key_usage = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
}
