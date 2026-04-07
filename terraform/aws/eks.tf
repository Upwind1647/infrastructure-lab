resource "aws_iam_role" "eks_cluster" {
  count = var.enable_eks ? 1 : 0

  name = "${var.eks_cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  lifecycle {
    precondition {
      condition     = var.enable_cost_budget
      error_message = "enable_cost_budget must be true before enable_eks can be used."
    }
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node" {
  count = var.enable_eks ? 1 : 0

  name = "${var.eks_cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "main" {
  count = var.enable_eks ? 1 : 0

  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    endpoint_public_access  = var.eks_endpoint_public_access
    endpoint_private_access = var.eks_endpoint_private_access
    public_access_cidrs     = [var.home_ip]
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = merge(
    {
      Name      = var.eks_cluster_name
      Role      = "KubernetesControlPlane"
      CostModel = "WeekendLifecycle"
    },
    var.eks_additional_tags,
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}

resource "aws_eks_node_group" "main" {
  count = var.enable_eks ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${var.eks_cluster_name}-ng"
  node_role_arn   = aws_iam_role.eks_node[0].arn
  subnet_ids      = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  instance_types = [var.eks_node_instance_type]
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"

  tags = merge(
    {
      Name      = "${var.eks_cluster_name}-ng"
      Role      = "KubernetesWorker"
      CostModel = "WeekendLifecycle"
    },
    var.eks_additional_tags,
  )

  lifecycle {
    precondition {
      condition = (
        var.eks_node_min_size <= var.eks_node_desired_size &&
        var.eks_node_desired_size <= var.eks_node_max_size
      )
      error_message = "EKS node scaling configuration must satisfy min <= desired <= max."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]
}

data "tls_certificate" "eks_oidc" {
  count = var.enable_eks ? 1 : 0

  url = aws_eks_cluster.main[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.enable_eks ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main[0].identity[0].oidc[0].issuer
}

# --- EKS Admin User (Bypasses Root Account Limits) ---
resource "aws_iam_user" "eks_admin" {
  count = var.enable_eks ? 1 : 0
  name  = "lab-eks-admin"
}

resource "aws_iam_user_policy_attachment" "eks_admin_policy" {
  count      = var.enable_eks ? 1 : 0
  user       = aws_iam_user.eks_admin[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_access_key" "eks_admin" {
  count = var.enable_eks ? 1 : 0
  user  = aws_iam_user.eks_admin[0].name
}

resource "aws_eks_access_entry" "eks_admin" {
  count         = var.enable_eks ? 1 : 0
  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_iam_user.eks_admin[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "eks_admin" {
  count         = var.enable_eks ? 1 : 0
  cluster_name  = aws_eks_cluster.main[0].name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_iam_user.eks_admin[0].arn

  access_scope {
    type = "cluster"
  }
}
