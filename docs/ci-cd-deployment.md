# E-commerce CI/CD Deployment

## Project overview

This project uses GitHub Actions to validate, build, publish, and deploy
Docker images to AWS.

## CI/CD pipeline

1. Push to the main branch triggers GitHub Actions.
2. Backend syntax and frontend build checks run.
3. GitHub Actions authenticates to AWS using OIDC.
4. Backend and frontend images are pushed to Amazon ECR.
5. AWS Systems Manager sends deployment commands to EC2.
6. The deployment script replaces application containers and checks health.
7. MongoDB is not recreated during application deployment.

## AWS resources

- Region: us-east-2
- ECR repositories: ecommerce-backend, ecommerce-frontend
- Deployment: AWS Systems Manager
- Entry point: Application Load Balancer

## Verification

The frontend and backend products API were checked through the ALB.
Both returned HTTP 200.

## Security

- AWS access uses GitHub OIDC.
- Do not commit real credentials, JWT secrets, .env files, or Terraform state.
- HTTPS and custom-domain configuration are outside this CI/CD phase.
