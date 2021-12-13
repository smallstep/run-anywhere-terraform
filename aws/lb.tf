# AWS load balancer controller

resource "aws_iam_policy" "load-balancer-policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "AWS LoadBalancer Controller IAM Policy"

  policy = file("resources/lb/iam-policy.json")
}

resource "aws_iam_role_policy" "load-balancer-role-policy" {
  name = "${local.default_name}-lb-all-nodes"
  role = aws_iam_role.eks_node_group.id

  policy = file("resources/lb/iam-policy.json")
}

resource "null_resource" "post-policy" {
  depends_on=[aws_eks_cluster.eks, aws_iam_policy.load-balancer-policy]

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
        ./resources/lb/post-policy.sh $reg $cn $acc
        echo "done"
     EOT
  }
}
