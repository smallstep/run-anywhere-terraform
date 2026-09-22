output "job_name" {
  description = "The bootstrap Job. After rotating a Secrets Manager value: kubectl -n <namespace> delete job <this>, then terraform apply — refresh notices the deletion and re-runs the chain, whose stages all converge on the new values."
  value       = kubernetes_job_v1.bootstrap.metadata[0].name
}
