# Define the Terraform provider (AWS)
provider "aws" {
  region = "ap-south-1"  # Adjust the region as necessary
}

# Create an IAM role for ECS task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

# Attach the ECS Task Execution policy to the role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}


# Create an ECR repository
resource "aws_ecr_repository" "flask_repo" {
  name = "flask-app-repo"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create a subnet
resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
}

# Create a security group
resource "aws_security_group" "ecs_sg" {
  name        = "ecs_security_group"
  description = "Allow inbound traffic to ECS container"
  vpc_id      = aws_vpc.main.id
}

# Allow inbound traffic to port 5000 (Flask app)
resource "aws_security_group_rule" "allow_http_inbound" {
  type        = "ingress"
  from_port   = 5000
  to_port     = 5000
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_sg.id
}

# Create an ECS cluster
resource "aws_ecs_cluster" "flask_cluster" {
  name = "flask-app-cluster"
}

# Create an ECS task definition
resource "aws_ecs_task_definition" "flask_task" {
  family                = "flask-task"
  requires_compatibilities = ["FARGATE"]
  network_mode          = "awsvpc"
  cpu                   = "256"
  memory                = "512"
  execution_role_arn    = aws_iam_role.ecs_task_execution_role.arn  # Add this line

  container_definitions = jsonencode([{
    name      = "flask-app"
    image     = "${aws_ecr_repository.flask_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 5000
      hostPort      = 5000
      protocol      = "tcp"
    }]
  }])
}


# Create an ECS service
resource "aws_ecs_service" "flask_service" {
  name            = "flask-service"
  cluster         = aws_ecs_cluster.flask_cluster.id
  task_definition = aws_ecs_task_definition.flask_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = [aws_subnet.main.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

# Output the URL of the ECS service (Elastic Load Balancer URL)
output "ecs_service_url" {
  value = aws_ecs_service.flask_service.id
}
