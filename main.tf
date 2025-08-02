# main.tf
provider "aws" {
  region = "us-east-1"
}

# API Gateway
resource "aws_api_gateway_rest_api" "service1_api" {
  name        = "service1-api"
  description = "API Gateway for Service 1"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.service1_api.id
  parent_id   = aws_api_gateway_rest_api.service1_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.service1_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.service1_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  uri                     = "http://${aws_lb.service1_alb.dns_name}/{proxy}"
}

# ALB for Service 1 (EC2)
resource "aws_lb" "service1_alb" {
  name               = "service1-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.service1_sg.id]
  subnets            = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]
}

# Auto Scaling Group for Service 1 (EC2)
resource "aws_launch_template" "service1_lt" {
  name_prefix   = "service1-"
  image_id      = "ami-12345678" # Amazon Linux 2 with Java
  instance_type = "t3.micro"
  user_data     = base64encode(<<-EOF
                #!/bin/bash
                yum install java-11-amazon-corretto -y
                wget -O service1.jar https://your-artifact-repo/service1-latest.jar
                java -jar service1.jar --server.port=8080 --service2.url=http://${aws_lb.service2_alb.dns_name}
                EOF
              )
}

resource "aws_autoscaling_group" "service1_asg" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]
  target_group_arns    = [aws_lb_target_group.service1_tg.arn]

  launch_template {
    id      = aws_launch_template.service1_lt.id
    version = "$Latest"
  }
}

# ECS Cluster for Service 2
resource "aws_ecs_cluster" "service2_cluster" {
  name = "service2-cluster"
}

resource "aws_ecs_task_definition" "service2_task" {
  family                   = "service2"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "service2-container",
    image     = "your-ecr-repo/service2:latest",
    essential = true,
    portMappings = [{
      containerPort = 8080,
      hostPort      = 8080
    }]
  }])
}

resource "aws_ecs_service" "service2" {
  name            = "service2"
  cluster         = aws_ecs_cluster.service2_cluster.id
  task_definition = aws_ecs_task_definition.service2_task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id]
    security_groups  = [aws_security_group.service2_sg.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.service2.arn
  }
  
#  load_balancer {
#    target_group_arn = aws_lb_target_group.service2_tg.arn
#    container_name   = "service2-container"
#    container_port   = 8080
#  }

  # Auto Scaling for ECS Service
#  deployment_controller {
#    type = "ECS"
#  }

}

# Auto Scaling for ECS Service 2
resource "aws_appautoscaling_target" "service2_scale_target" {
  max_capacity       = 5
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.service2_cluster.name}/${aws_ecs_service.service2.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "service2_scale_up" {
  name               = "service2-scale-up"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service2_scale_target.resource_id
  scalable_dimension = aws_appautoscaling_target.service2_scale_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.service2_scale_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70
  }
}

# ALB for Service 2 (ECS)
#resource "aws_lb" "service2_alb" {
#  name               = "service2-alb"
#  internal           = true
#  load_balancer_type = "application"
#  security_groups    = [aws_security_group.service2_sg.id]
#  subnets            = [aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id]
#}

# VPC Networking (simplified)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "private_subnet1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
}

# Security Groups
resource "aws_security_group" "service1_sg" {
  vpc_id = aws_vpc.main.id
  # Allow HTTP from API Gateway and between services
}

resource "aws_security_group" "service2_sg" {
  vpc_id = aws_vpc.main.id
  # Allow HTTP from Service 1 only
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.service1_deployment.invoke_url
}

resource "aws_service_discovery_private_dns_namespace" "ecs" {
  name        = "ecs.internal"
  vpc         = aws_vpc.main.id
}

resource "aws_service_discovery_service" "service2" {
  name = "service2"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.ecs.id

    dns_records {
      ttl  = 60
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 2
  }
}

resource "aws_security_group_rule" "service1_to_cloudmap" {
  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  security_group_id = aws_security_group.service1_sg.id
  cidr_blocks       = ["0.0.0.0/0"]  # Or restrict to VPC CIDR
}

