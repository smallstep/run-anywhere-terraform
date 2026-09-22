output "namespace" {
  value = data.terraform_remote_state.platform.outputs.namespace
}

output "bootstrap_job_name" {
  description = "Re-run secret/database bootstrap after a rotation with: kubectl -n <ns> delete job <name> && terraform apply (the job is recreated)."
  value       = module.smallstep_bootstrap.job_name
}
