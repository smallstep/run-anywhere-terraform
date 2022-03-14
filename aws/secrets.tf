#------------------------------------------------------------------------------------- 
# 
# This file is where we set up KMS Keys, SecretsManager secrets, and related resources
# 
#-------------------------------------------------------------------------------------

# Before we set up any other resources, we'll need to create a KMS key and use it to
# encrypt the following secrets
resource "aws_kms_key" "smallstep" {
  description         = "KMS key used for encrypting/decrypting secrets related to the Smallstep Integration"
  key_usage           = "ENCRYPT_DECRYPT"
  enable_key_rotation = false

  tags = {
    Name      = var.default_name
    ManagedBy = var.default_description
  }
}

# This secret is procedurally generated and populated by a null resource below
resource "aws_secretsmanager_secret" "auth_secret" {
  name                    = "${var.default_name}-auth-secret"
  description             = "${var.default_name} authentication secret used by EKS"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period

  tags = {
    Name        = "${var.default_name}-auth-secret"
    Description = var.default_description
  }
}

# This (optional) secret is set by the user by specifying the value of variable yubihsm_pin in an apply
resource "aws_secretsmanager_secret" "yubihsm_pin" {
  count = var.yubihsm_enabled == true ? 1 : 0

  name                    = "${var.default_name}-hsm-pin"
  description             = "${var.default_name} pin used by project HSMs"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period

  tags = {
    Name        = "${var.default_name}-hsm-pin"
    Description = var.default_description
  }
}

# This secret is procedurally generated and populated by a null resource below
resource "aws_secretsmanager_secret" "majordomo_secret" {
  name                    = "${var.default_name}-majordomo-secret"
  description             = "${var.default_name} secret used by majordomo service in EKS"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period

  tags = {
    Name        = "${var.default_name}-majordomo-secret"
    Description = var.default_description
  }
}

# Login info for all databases used by the project
resource "aws_secretsmanager_secret" "master_password" {
  name                    = "${var.default_name}-db-login-info"
  description             = "${var.default_name} database login info used by lambda"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period

  tags = {
    Name        = "${var.default_name}-db-login-info"
    Description = var.default_description
  }
}

# Only the db password string for kubernetes secrets
resource "aws_secretsmanager_secret" "master_password_string" {
  name                    = "${var.default_name}-db-password"
  description             = "${var.default_name} database password used by EKS"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period

  tags = {
    Name        = "${var.default_name}-db-password"
    Description = var.default_description
  }
}

# This secret is procedurally generated and populated by /scripts/create_secrets.sh
resource "aws_secretsmanager_secret" "oidc_jwks" {
  name                    = "${var.default_name}-oidc-jwks"
  description             = "${var.default_name} OIDC JWKS public key used by EKS"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period

  tags = {
    Name        = "${var.default_name}-oidc-jwks"
    Description = var.default_description
  }
}

# There are 2 required user-input passwords: smtp_password & private_issuer_password
# Pass these in as variables in your first `terraform apply` or you will get errors
resource "aws_secretsmanager_secret" "private_issuer_password" {
  name                    = "${var.default_name}-private-issuer-password"
  description             = "${var.default_name} private issuer password used by EKS"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period
  
  tags = {
    Name        = "${var.default_name}-private-issuer-password"
    Description = var.default_description
  }
}

# Creates an empty secret to be filled in by the user
resource "aws_secretsmanager_secret" "scim_key" {
  name                    = "${var.default_name}-scim-key"
  description             = "${var.default_name} SCIM private key used by EKS"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period

  tags = {
    Name        = "${var.default_name}-scim-key"
    Description = "Please modify by hand if using SCIM provisioning."
  }
}

resource "aws_secretsmanager_secret" "smtp_password" {
  name                    = "${var.default_name}-smtp-password"
  description             = "${var.default_name} SMTP password used by EKS"
  kms_key_id              = aws_kms_key.smallstep.id
  recovery_window_in_days = var.backup_retention_period

  tags = {
    Name        = "${var.default_name}-smtp-password"
    Description = var.default_description
  }
}

# Instantiate the above secrets with their given values
resource "aws_secretsmanager_secret_version" "auth_secret" {
  secret_id = aws_secretsmanager_secret.auth_secret.id
  secret_string = random_password.auth_secret.result
}

resource "aws_secretsmanager_secret_version" "yubihsm_pin" {
  count = var.yubihsm_enabled == true ? 1 : 0

  secret_id     = aws_secretsmanager_secret.yubihsm_pin[count.index].id
  secret_string = var.yubihsm_pin

  # This variable will only be set the first time running terraform and will change to ""
  # Don't wipe the password when this happens
  lifecycle {
    ignore_changes  = [secret_string]
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "majordomo_secret" {
  secret_id = aws_secretsmanager_secret.majordomo_secret.id
  secret_string = random_password.majordomo_secret.result
}

resource "aws_secretsmanager_secret_version" "master_password_initial" {
  secret_id = aws_secretsmanager_secret.master_password.id
  secret_string = jsonencode(local.master_creds)
}

resource "aws_secretsmanager_secret_version" "master_password_string" {
  secret_id = aws_secretsmanager_secret.master_password_string.id
  secret_string = random_password.initial_master_password.result
}

resource "aws_secretsmanager_secret_version" "private_issuer_password" {
  secret_id     = aws_secretsmanager_secret.private_issuer_password.id
  secret_string = var.private_issuer_password

  # This variable will only be set the first time running terraform and will change to ""
  # Don't wipe the password when this happens
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret_version" "smtp_password" {
  secret_id     = aws_secretsmanager_secret.smtp_password.id
  secret_string = var.smtp_password

  # This variable will only be set the first time running terraform and will change to ""
  # Don't wipe the password when this happens
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Once the KMS key has been created, we generate client secrets for the key to encrypt
resource "null_resource" "generate_oidc_jwk" {
  provisioner "local-exec" {
    command     = "${path.module}/scripts/create_oidc_secret.sh"

    environment = {
      secret_id = aws_secretsmanager_secret.oidc_jwks.id
    }
  } 
}

# We also generate a temporary SCIM key for the cluster to reference
# If using SCIM for provisioning, replace this value in SecretsManager and re-apply
resource "null_resource" "generate_temp_scim_key" {
  provisioner "local-exec" {
    command     = "${path.module}/scripts/create_temp_scim_key.sh"

    environment = {
      secret_id = aws_secretsmanager_secret.scim_key.id
    }
  } 
}

# Randomly generated password for the auth secret
resource "random_password" "auth_secret" {
  length           = 32
  special          = false
}

# Generate a randomized master password for the database clusters
resource "random_password" "initial_master_password" {
  length = 32
  special = "false"
}

# Randomly generated password for majordomo
resource "random_password" "majordomo_secret" {
  length           = 32
  special          = false
}
