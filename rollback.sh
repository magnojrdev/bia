#!/bin/bash

set -e

# Configurações
REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"

if [ -z "$1" ]; then
    echo "Uso: $0 <commit-hash>"
    echo "Exemplo: $0 abc1234"
    exit 1
fi

TARGET_TAG=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

echo "Rollback iniciado para versão: $TARGET_TAG"

# Verificar se a imagem existe
if ! aws ecr describe-images --repository-name $ECR_REPO --region $REGION --image-ids imageTag=$TARGET_TAG > /dev/null 2>&1; then
    echo "ERRO: Imagem com tag '$TARGET_TAG' não encontrada no ECR"
    exit 1
fi

# Criar nova task definition com a imagem de rollback
aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition' > temp-task.json

jq --arg image "$ECR_URI:$TARGET_TAG" '.containerDefinitions[0].image = $image | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' temp-task.json > new-task.json

NEW_REVISION=$(aws ecs register-task-definition --region $REGION --cli-input-json file://new-task.json --query 'taskDefinition.revision' --output text)

# Atualizar serviço
aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$NEW_REVISION

# Cleanup
rm -f temp-task.json new-task.json

echo "Rollback concluído! Versão: $TARGET_TAG (Revision: $NEW_REVISION)"
