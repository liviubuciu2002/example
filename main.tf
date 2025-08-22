terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      #version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Shared Networking Resources
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "services-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# X-Ray Resources
resource "aws_xray_group" "services_group" {
  group_name        = "ServicesGroup"
  filter_expression = "service(\"service1*\") OR service(\"service2*\")"
}

resource "aws_iam_role_policy_attachment" "xray_write_access_ecs" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "xray_write_access_ec2" {
  role       = aws_iam_role.service1.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Service2 - ECS with Cloud Map
resource "aws_ecs_cluster" "service2_cluster" {
  name = "service2-cluster"
}

resource "aws_cloudwatch_log_group" "service2" {
  name = "/ecs/service2"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_service_discovery_private_dns_namespace" "service2" {
  name        = "service2.local"
  description = "Service discovery namespace for Service2"
  vpc         = aws_vpc.main.id
}

resource "aws_service_discovery_service" "service2" {
  name = "service2"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.service2.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "service2" {
  family                   = "service2"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "service2-container"
    image     = "public.ecr.aws/t8o8w5f1/liviubuciunamespace/service2:v1.1"
    essential = true
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
      protocol = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service2.name
        "awslogs-region"       = "us-east-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  },
    {
      name      = "xray-daemon"
      image     = "amazon/aws-xray-daemon"
      essential = true
      cpu       = 32
      memory    = 256
      portMappings = [
        {
          containerPort = 2000
          hostPort      = 2000
          protocol      = "udp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service2.name
          "awslogs-region"       = "us-east-1"
          "awslogs-stream-prefix" = "xray"
        }
      }
    }])
}

resource "aws_security_group" "service2" {
  name        = "service2-sg"
  description = "Allow inbound access to Service2 only from Service1"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    #security_groups = [aws_security_group.service1.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "service2" {
  name            = "service2"
  cluster         = aws_ecs_cluster.service2_cluster.id
  task_definition = aws_ecs_task_definition.service2.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.service2.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.service2.arn
  }
}

resource "tls_private_key" "my_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "my-terraform-key"
  public_key = tls_private_key.my_key.public_key_openssh
}

resource "local_file" "my_key_private" {
  content  = tls_private_key.my_key.private_key_pem
  filename = "my-terraform-key.pem"
  file_permission = "0400"
}

# Service1 - Auto-scalable EC2 with Docker
resource "aws_launch_template" "service1" {
  name_prefix   = "service1-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.generated_key.key_name
  #key_name      = "your-key-pair"

  iam_instance_profile {
    name = aws_iam_instance_profile.service1.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 30
      volume_type = "gp2"
    }
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups            = [aws_security_group.service1.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.service2_cluster.name}" >> /etc/ecs/ecs.config
              yum install -y docker
              systemctl enable docker
              systemctl start docker

              # Install and start X-Ray daemon
              curl https://s3.us-east-1.amazonaws.com/aws-xray-assets.us-east-1/xray-daemon/aws-xray-daemon-3.x.rpm -o /tmp/xray.rpm
              yum install -y /tmp/xray.rpm
              systemctl start xray

              docker run -d -p 8080:8080 --name service1 public.ecr.aws/t8o8w5f1/liviubuciunamespace/mydockerimages:latest
              EOF
  )
}

resource "aws_autoscaling_group" "service1" {
  name_prefix          = "service1-asg-"
  vpc_zone_identifier  = aws_subnet.public[*].id
  desired_capacity     = 2
  min_size             = 1
  max_size             = 4
  health_check_type    = "EC2"

  launch_template {
    id      = aws_launch_template.service1.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "service1-instance"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "service1" {
  name        = "service1-sg"
  description = "Allow HTTP to Service1 and outbound to Service2"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # WARNING: This allows SSH from anywhere. See below for a more secure option.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_instance_profile" "service1" {
  name = "service1-instance-profile"
  role = aws_iam_role.service1.name
}

resource "aws_iam_role" "service1" {
  name = "service1-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "service1_ec2" {
  role       = aws_iam_role.service1.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy" "service1_cloudmap" {
  name = "service1-cloudmap"
  role = aws_iam_role.service1.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "servicediscovery:DiscoverInstances"
        ],
        Effect   = "Allow"
        Resource = aws_service_discovery_service.service2.arn
      }
    ]
  })
}

data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# Outputs
# output "service1_endpoint" {
#   value = "http://${one(aws_autoscaling_group.service1)}"
# }

output "service2_discovery_name" {
  value = "${aws_service_discovery_service.service2.name}.${aws_service_discovery_private_dns_namespace.service2.name}"
}

output "xray_group_arn" {
  value = aws_xray_group.services_group.arn
}