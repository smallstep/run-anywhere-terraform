## Notes

Even though the AzureIdentity and AzureIdentityBinding configs have a dependency on the AAD Pod Identity Helm chart, terraform was unable to create those resources because the CRD had not been applied. I had to run `terraform apply -target module.run_anywhere.helm_release.aad_pod_identity` before the aadpodidentity.k8s.io resources could be created.


I had to `terraform import module.run_anywhere.kubernetes_config_map_v1.coredns_custom kube-system/coredns-custom` because AKS automatically ensures it exists.
