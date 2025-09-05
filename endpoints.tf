module "endpoints" {
    source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

    vpc_id = module.vpc.vpc_id
    security_group_ids = [
            module.vpc_endpoint_sg.security_group_id
    ]

endpoints ={
    s3 = {
        service = "s3"
        tags = { Name = "s3-vpc-endpoint" }
    }
}

}