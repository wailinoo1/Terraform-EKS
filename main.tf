module "network" {
  source = "./Network"
  vpc_cidr_block   = "10.200.0.0/16"
  vpcname = "wlo-terraform-vpc"
  subnet-name = "terraform-subnet"
  wlo-terraform-igw-name = "wlo-terraform-igw"
  natgw-name = "terraform-nat-gw"
  publicrtname = "public-subnet-routetable"
  privatertname = "private-subnet-routetable"
}

module "eks" {
  source = "./eks"
  vpc_id = module.network.vpcid
  cluster = "wlo-eks-terraform"
  cluser_role = "eks-cluster-role-terraform"
  nodegroup_name = "eks-nodegroup"
  nodegrouprole = "eks-nodegrouprole"
  subnetid = module.network.subnetid
}