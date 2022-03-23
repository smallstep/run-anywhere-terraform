#----------------------------------------------------------------------------------
# 
# This file is where we set up resources to support the EKS LB Controller
# 
#----------------------------------------------------------------------------------

resource "aws_iam_policy" "load_balancer_policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "AWS LoadBalancer Controller IAM Policy"

  policy = file("${path.module}/resources/lb/iam-policy.json")
}

resource "aws_iam_role_policy" "load_balancer_role_policy" {
  name = "${var.default_name}-lb-all-nodes"
  role = aws_iam_role.eks_node_group.id

  policy = file("${path.module}/resources/lb/iam-policy.json")
}

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
        ${path.module}/resources/lb/post-policy.sh $reg $cn $acc
        echo "done"
     EOT
  }

  depends_on = [aws_eks_cluster.eks, aws_iam_policy.load_balancer_policy]
}
