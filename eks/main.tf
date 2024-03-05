####create role for EKS Cluster
data "aws_iam_policy_document" "eksclusterroledoc"{
    statement {
        actions = [ "sts:AssumeRole"]

        principals {
            type        = "Service"
            identifiers = ["eks.amazonaws.com"]
    }
        effect = "Allow"

   }
}
resource "aws_iam_role" "terraformeksclusterole" {
  name               = var.cluser_role
  assume_role_policy = data.aws_iam_policy_document.eksclusterroledoc.json
}

resource "aws_iam_role_policy_attachment" "eksroleattach" {
  role       = aws_iam_role.terraformeksclusterole.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

####Create Log Group for EKS Cluster
resource "aws_cloudwatch_log_group" "Log" {
  name              = "/aws/eks/${var.cluster}/cluster"
  retention_in_days = 7

}


resource "aws_eks_cluster" "terraform-eks" {
  name     = var.cluster
  role_arn = aws_iam_role.terraformeksclusterole.arn

  vpc_config {
    subnet_ids = [for subnet in var.subnetid : subnet ]
    endpoint_public_access  = true
    endpoint_private_access = true
  }
  enabled_cluster_log_types = ["api", "audit"]
   depends_on = [
    aws_iam_role_policy_attachment.eksroleattach,
    aws_cloudwatch_log_group.Log
  ]
  
}


resource "aws_iam_role" "terraformnodegrouprole" {
  name = var.nodegrouprole

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.terraformnodegrouprole.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.terraformnodegrouprole.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.terraformnodegrouprole.name
}

resource "aws_security_group" "eks-ng-sg" {
  name        = "eks-nodegroup-sg"
  description = "NodeGroup SG"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Ingress rule allowing traffic from the VPC CIDR
  ingress {
    from_port   = 0    # Adjust the source port if needed
    to_port     = 0    # Adjust the destination port if needed
    protocol    = "-1" # Allow all protocols
    cidr_blocks = ["10.200.0.0/16"]
  }
}


resource "aws_launch_template" "template" {
  name = "wai-eks-launchtemplate"

  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size = 100
      iops = 3000
      throughput = 300
      volume_type = "gp3"    
    }
  }
  network_interfaces {
    associate_public_ip_address = false
    security_groups = [aws_security_group.eks-ng-sg]
  }

  image_id = var.image_id
  instance_type = var.instance_type
  
  
  user_data = base64encode(<<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="
--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"
#!/bin/bash
/etc/eks/bootstrap.sh ${var.cluster}

--==MYBOUNDARY==--\
  EOF
  )
  depends_on = [ aws_eks_cluster.terraform-eks ]

}



resource "aws_eks_node_group" "nodegroup" {
  cluster_name    = aws_eks_cluster.terraform-eks.name
  node_group_name = var.nodegroup_name
  node_role_arn   = aws_iam_role.terraformnodegrouprole.arn
  subnet_ids      = [for subnet in var.subnetid : subnet]

  capacity_type = "ON_DEMAND"

  launch_template {
    name = aws_launch_template.template.name
    version = aws_launch_template.template.latest_version
  }


  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }

  update_config {
    max_unavailable = 2
  }

  
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    aws_launch_template.template
  ]
}