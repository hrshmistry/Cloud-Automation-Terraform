#------------------------ Provider -----------------------------

#Describing Provider
provider "aws" {
  region     = "ap-south-1"
  profile    = "harsh"
}

#------------------------ Variables -----------------------------

#Creating Variable for AMI Id
variable "ami_id" {
  type    = string
  default = "ami-0447a12f28fddb066"
}

#Creating Variable for AMI Type
variable "ami_type" {
  type    = string
  default = "t2.micro"
}

#Creating Variable for key
variable "EC2_Key" {
  type    = string
  default = "Task1Key"
}

#-------------------------- Key-Pair ----------------------------

#Creating tls_private_key using RSA algorithm 

resource "tls_private_key" "tls_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#Generating Key-Value Pair
resource "aws_key_pair" "generated_key" {
  depends_on = [
    tls_private_key.tls_key
  ]

  key_name   = var.EC2_Key
  public_key = tls_private_key.tls_key.public_key_openssh
}

#Saving Private Key PEM File
resource "local_file" "key-file" {
  depends_on = [
    tls_private_key.tls_key
  ]

  content  = tls_private_key.tls_key.private_key_pem
  filename = var.EC2_Key
}

#----------------------- Security-group ------------------------

resource "aws_security_group" "firewall" {
  depends_on = [
      aws_key_pair.generated_key
  ]

  name         = "firewall"
  description  = "allows ssh and httpd protocol"
  
  #Adding Rules to Security Group
  ingress {
    description = "SSH Port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    
  ingress {
    description = "HTTPD Port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "security-group-1"
  }
}

#---------------------- Launch EC2 instance ---------------------

resource "aws_instance" "autos" {
  depends_on = [
      aws_security_group.firewall
  ]

  ami           = var.ami_id
  instance_type = var.ami_type
  key_name	    = var.EC2_Key
  security_groups = ["${aws_security_group.firewall.name}"]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tls_key.private_key_pem
    host     = aws_instance.autos.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"
    ]
  }

  tags = {
    Name = "autos"
    env  = "Production"
  }
}

#-------------------------- EBS Volume -------------------------

#Creating EBS volume and attaching it to EC2 Instance.
resource "aws_ebs_volume" "ebs" {
  availability_zone = aws_instance.autos.availability_zone
  size              = 1

  tags = {
    Name = "autos_ebs"
  }
}

/*
variable "volume_name" {
  type    = string
  default = "dh"
}
*/

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs.id
  instance_id = aws_instance.autos.id
  force_detach = true
}

output "autos_public_ip" {
  value = aws_instance.autos.public_ip
}

resource "null_resource" "print_public_ip" {
  provisioner "local-exec" {
    command = "echo ${aws_instance.autos.public_ip} > autos_public_ip.txt"
  }
}

#----- Mounting the Volume in EC2 Instance and Cloning GitHub -----

resource "null_resource" "mount_ebs_volume" {
  depends_on = [
    aws_volume_attachment.ebs_att
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tls_key.private_key_pem
    host     = aws_instance.autos.public_ip
  }

  provisioner "remote-exec" {
      inline = [
        "sudo mkfs.ext4 /dev/xvdh",
        "sudo mount /dev/xvdh /var/www/html",
        "sudo rm -rf /var/www/html",
        "sudo git clone https://github.com/hrshmistry/Code-Cloud.git /var/www/html/"
      ]
    }
}

#---------------------- Creating S3 bucket ------------------------

resource "aws_s3_bucket" "S3" {
  bucket = "autos-s3-bucket"
  acl    = "public-read"
}

#Putting Objects in S3 Bucket
resource "aws_s3_bucket_object" "S3_Object" {
  depends_on = [
    aws_s3_bucket.S3
  ]

  bucket = aws_s3_bucket.S3.bucket
  key    = "Cloud.JPG"
  source = "D:/LW/Hybrid-Multi-Cloud/Terraform/tera/task/Cloud.JPG"
  acl    = "public-read"
}

#------------ Creating CloutFront with S3 Bucket Origin -------------

locals {
  S3_Origin_Id = aws_s3_bucket.S3.id
}

resource "aws_cloudfront_distribution" "CloudFront" {
  depends_on = [
    aws_s3_bucket_object.S3_Object
  ]

  origin {
    domain_name = aws_s3_bucket.S3.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.S3.id
    # OR origin_id   = local.S3_Origin_Id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 Web Distribution"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.S3.id
    # OR origin_id   = local.S3_Origin_Id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.S3.id
    # OR origin_id   = local.S3_Origin_Id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.S3.id
    # OR origin_id   = local.S3_Origin_Id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Name        = "CF Distribution"
    Environment = "Production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  retain_on_delete = true
}

#------ Changing the html code and adding the image url in that ------

resource "null_resource" "CF_URL"  {
  depends_on = [
    aws_cloudfront_distribution.CloudFront
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tls_key.private_key_pem
    host     = aws_instance.autos.public_ip
  }
  
  provisioner "remote-exec" {
    inline = [
      "echo '<p align = 'center'>'",
      "echo '<img src='https://${aws_cloudfront_distribution.CloudFront.domain_name}/Cloud.JPG' width='100' height='100'>' | sudo tee -a /var/www/html/Slack.html",
      "echo '</p>'"
    ]
  }
}

#-------------------- Creating EBS snapshot volume --------------------

resource "aws_ebs_snapshot" "ebs_snapshot" {
  depends_on = [
   null_resource.CF_URL
  ]
    
  volume_id = aws_ebs_volume.ebs.id

  tags = {
    Name = "ebs_snap"
  }
}

#-------------------- using the infrastructure -----------------------

resource "null_resource" "web-server-site-on-browser" {
  depends_on = [
    null_resource.CF_URL
  ]

  provisioner "local-exec" {
    command = "brave ${aws_instance.autos.public_ip}/Slack.html"
  }
}