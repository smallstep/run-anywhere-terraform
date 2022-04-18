#----------------------------------------------------------------------------------
# 
# This file is where we set up resources to support the EKS LB Controller
# 
#----------------------------------------------------------------------------------

data "http" "load_balancer_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v${var.k8s_alb_controller_version}/docs/install/iam_policy.json"

  request_headers = {
    Accept = "application/json"
  }
}

# Grants access for the aws-load-balancer-controller to create an NLB
resource "aws_iam_role_policy" "load_balancer_role_policy" {
  name = "${var.default_name}-lb-all-nodes"
  role = aws_iam_role.eks_node_group.id

  policy = data.http.load_balancer_policy.body
}

# 
resource "null_resource" "post_policy" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    on_failure  = fail
    interpreter = ["/bin/bash", "-c"]
    when = create
    command     = <<EOT
        reg=$(echo ${aws_eks_cluster.eks.arn} | cut -f4 -d':')
        acc=$(echo ${aws_eks_cluster.eks.arn} | cut -f5 -d':')
        cn=$(echo ${aws_eks_cluster.eks.name})
        echo "$reg $cn $acc"
        kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
        ${path.module}/resources/lb/post-policy.sh $reg $cn $acc ${var.k8s_alb_controller_version}
        echo "done"
     EOT
  }

  depends_on = [aws_eks_cluster.eks, aws_iam_role_policy.load_balancer_role_policy]
}
