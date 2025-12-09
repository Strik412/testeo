#!/bin/bash
set -e

# Este script es ejecutado por GitHub Actions para desplegar Docker en las instancias EC2

INSTANCES=$1
DOCKER_IMAGE=$2
REGION=${3:-us-east-1}

if [ -z "$INSTANCES" ] || [ -z "$DOCKER_IMAGE" ]; then
  echo "Usage: deploy-to-instances.sh '<instance_ids>' '<docker_image>' [region]"
  echo "Example: deploy-to-instances.sh 'i-123456 i-789012' 'myuser/myimage:latest' 'us-east-1'"
  exit 1
fi

echo "🚀 Deploying $DOCKER_IMAGE to instances: $INSTANCES"

for INSTANCE_ID in $INSTANCES; do
  echo "📦 Deploying to instance: $INSTANCE_ID"
  
  # Usar AWS Systems Manager para ejecutar comandos
  aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=[
      "#!/bin/bash",
      "set -e",
      "echo \"Pulling Docker image $DOCKER_IMAGE...\"",
      "docker pull '$DOCKER_IMAGE'",
      "echo \"Stopping old container...\"",
      "docker rm -f app || true",
      "echo \"Starting new container...\"",
      "docker run -d --name app -p 80:80 '$DOCKER_IMAGE'",
      "echo \"✅ Deployment completed on $INSTANCE_ID\""
    ]' \
    --targets "Key=instanceids,Values=$INSTANCE_ID" \
    --region "$REGION" \
    --output json
  
  echo "✅ Command sent to $INSTANCE_ID"
done

echo "✅ All deployments initiated!"
