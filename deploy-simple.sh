#!/bin/bash

set -e

# Configurações
REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"

# Obter commit hash
COMMIT_HASH=$(git rev-parse --short=7 HEAD)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

echo "Deploy iniciado - Commit: $COMMIT_HASH"

# Login ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URI

# Build e push
docker build -t $ECR_URI:$COMMIT_HASH .
docker push $ECR_URI:$COMMIT_HASH

# Criar nova task definition
aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition' > temp-task.json

# Atualizar imagem na task definition
jq --arg image "$ECR_URI:$COMMIT_HASH" '.containerDefinitions[0].image = $image | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' temp-task.json > new-task.json

# Registrar nova task definition
NEW_REVISION=$(aws ecs register-task-definition --region $REGION --cli-input-json file://new-task.json --query 'taskDefinition.revision' --output text)

# Atualizar serviço
aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$NEW_REVISION

# Cleanup
rm -f temp-task.json new-task.json

echo "Deploy concluído! Versão: $COMMIT_HASH (Revision: $NEW_REVISION)"
