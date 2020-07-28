provider "aws" {
	profile = "Kajal"
	region = "ap-south-1"
}

#Creating vpc:

resource "aws_vpc" "lwvpc" {
	cidr_block = "10.0.0.0/16"
	tags = {
	        Name = "MY VPC"
	}
}

resource "aws_subnet" "lwsubnet" {
	tags = {
	             Name = "LW-SUBNET"
	}
	vpc_id =aws_vpc.lwvpc.id
	cidr_block = "10.0.1.0/24"
	map_public_ip_on_launch = true
	depends_on = [aws_vpc.lwvpc ]
}

resource "aws_route_table" "route_table" {
	tags = {
		Name = "Route_Table"
	}
	vpc_id=aws_vpc.lwvpc.id
}
resource "aws_route_table_association" "Route_table_Association" {
	subnet_id      = aws_subnet.lwsubnet.id
	route_table_id = aws_route_table.route_table.id
}

resource "aws_internet_gateway" "Internet_gateway" {
	tags = {
		Name = "IGW"
	}
	vpc_id = aws_vpc.lwvpc.id
	depends_on = [aws_vpc.lwvpc] 
}

resource "aws_route" "default_route" {
	route_table_id = aws_route_table.route_table.id
	destination_cidr_block = "0.0.0.0/0"
	gateway_id = aws_internet_gateway.Internet_gateway.id
}

resource "aws_security_group" "Security_group" {
  name        = "Security_group"
  description = "Allow_tls"
  vpc_id      = "${aws_vpc.lwvpc.id}"

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
       description = "NFS"
       from_port = 2049
       to_port = 2049
       protocol = "tcp"
       cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "ping-icmp"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow_tls1"
  }
}

resource "tls_private_key" "example" {
  algorithm   = "RSA"
  rsa_bits = 4096
}

resource "local_file" "private-key" {
    content     = tls_private_key.example.private_key_pem
    filename = "mykey.pem"
    file_permission = 0400
}

resource "aws_key_pair" "key-pair" {
  key_name   = "mykey"
  public_key = tls_private_key.example.public_key_openssh
}

resource "aws_instance" "web" {
	ami = "ami-052c08d70def0ac62"
	instance_type = "t2.micro"
	tags = {
		Name = "lwos1"
	}
	subnet_id = aws_subnet.lwsubnet.id
	key_name = "mykey"
	security_groups = [aws_security_group.Security_group.id ] 
	provisioner "remote-exec" {
	connection { 
		type = "ssh"
		user = "ec2-user"
		private_key = tls_private_key.example.private_key_pem
		host     = aws_instance.web.public_ip
	}
	inline = [
		"sudo yum install httpd php git -y",
		"sudo systemctl restart httpd",
		"sudo systemctl enable httpd",
	]
} 
}

#Create efs file system
resource "aws_efs_file_system" "foo" {
  	depends_on = [aws_security_group.Security_group, aws_instance.web, ]
	creation_token = "my-product"

  tags = {
    Name = "MyProduct"
  }
}

#Mouting file system
resource "aws_efs_mount_target" "mount_target" {
	file_system_id = aws_efs_file_system.foo.id
	subnet_id = aws_instance.web.subnet_id
	security_groups = [ "${aws_security_group.Security_group.id}" ]
	depends_on = [ aws_efs_file_system.foo, ]
}

resource "null_resource" "EC2_mount" { 
	depends_on = [aws_efs_mount_target.mount_target, ]
	connection {
		type = "ssh" 
		user = "ec2-user"
		private_key = tls_private_key.example.private_key_pem
		host     = aws_instance.web.public_ip
	}
	provisioner "remote-exec" {
	inline = [
	"sudo mount -t nfs4 ${aws_efs_mount_target.mount_target.ip_address}:/ /var/www/html/",
	"sudo rm -rf /var/www/html/*",
	"sudo git clone https://github.com/kajal1706043/multi_cloudTask1.git /var/www/html"
	]
	}
}

/*Create an S3 bucket and grant public access to it */
resource "aws_s3_bucket" "bb" {
  bucket = "tsk2bucket"
  acl    = "public-read"

  tags = {
    Name        = "mybucket"
  }
}

/* Deploy an image into the bucket from Github. */
resource "aws_s3_bucket_object" "deployimage" {
	bucket = aws_s3_bucket.bb.bucket
	key = "CloudTask2.jpg"
	source = "git_image/Hybrid-Cloud.jpg"
	acl = "public-read"
}

/* null-resources are the first to be executed by Terraform. Thus, the image on github is first download onto the local machine*/

resource "null_resource" "nulllocal4" {
provisioner "local-exec" {
	command = "git clone https://github.com/kajal1706043/task1_s3.git git_image"
}
/* To remove the image from the local system when the infrastructure is destroyed */
provisioner "local-exec" {
	when = destroy
	command = "rmdir /s /q git_image"
}
}

#Create a CloudFront Distribution with the created S3 bucket as Origin
locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.bb.bucket_domain_name
    origin_id   = "${local.s3_origin_id}"
   
    default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
viewer_protocol_policy = "allow-all"
}
enabled             = true
restrictions {
     geo_restriction {
      	restriction_type = "none"
    }
}
viewer_certificate {
    cloudfront_default_certificate = true
  }
}
