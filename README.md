# End To End Cloud Infrastructure Automation Through Terraform by HashiCorp

## Things Included In This Project Are...

- Create the key and security group which allow the port 80.
- Launch EC2 instance.
- In this Ec2 instance use the key and security group which we have created.
- Launch one Volume (EBS) and mount that volume into /var/www/html.
- Developer have uploded the code into github repo also the repo has some images.
- Copy the github repo code into /var/www/html
- Create S3 bucket, and copy/deploy the images from github repo into the s3 bucket and change the permission to public readable.
- Create a Cloudfront using s3 bucket(which contains images) and use the Cloudfront URL to  update in code in /var/www/html
- create snapshot of ebs

### Above task is done only using terraform!
