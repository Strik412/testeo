# 🚀 Arquitectura: Terraform + GitHub Actions

## 📋 Cambios Realizados

### 1. **main.tf Modificado**

El archivo `main.tf` ahora:

✅ **Crea infraestructura sin desplegar Docker**
```hcl
# El user_data ya NO descarga ni ejecuta Docker
# Solo instala Docker y prepara el sistema
user_data = base64encode(<<-EOF
  #!/bin/bash
  yum update -y
  yum install -y docker git
  systemctl start docker
  systemctl enable docker
  usermod -a -G docker ec2-user
  
  # Waiting for GitHub Actions deployment
EOF
)
```

✅ **Añadido IAM Role para AWS Systems Manager**
```hcl
resource "aws_iam_role" "ec2_role"
resource "aws_iam_role_policy_attachment" "ssm_policy"
resource "aws_iam_instance_profile" "ec2_profile"
```

✅ **Nuevos Outputs para GitHub Actions**
```hcl
output "instance_ids"       # IDs de instancias
output "asg_name"          # Nombre del ASG
output "alb_dns_name"      # DNS del ALB
```

---

## 🔄 Flujo de Despliegue

```
┌─────────────────────────────────────────────────────────┐
│                    FASE 1: INFRAESTRUCTURA              │
│                    (Terraform Deploy)                   │
└──────────────┬──────────────────────────────────────────┘
               │
               ├─ Push a main con cambios en main.tf
               │
               ├─ GitHub Actions: terraform-deploy.yml
               │  ├─ terraform init
               │  ├─ terraform plan
               │  ├─ terraform apply
               │  └─ Crea: VPC, ALB, ASG, EC2 (sin Docker)
               │
               └─> ✅ Infraestructura lista

┌─────────────────────────────────────────────────────────┐
│                 FASE 2: DEPLOYMENT DOCKER              │
│              (GitHub Actions + AWS Systems Manager)     │
└──────────────┬──────────────────────────────────────────┘
               │
               ├─ Push a main con cambios en dockerfile/index.html
               │
               ├─ GitHub Actions: deploy.yml
               │  ├─ Build Docker image
               │  ├─ Push a Docker Hub
               │  ├─ Get instance IDs from ASG
               │  ├─ Send SSM commands a cada instancia
               │  │  └─ docker pull && docker run
               │  └─ Verify deployment
               │
               └─> ✅ Aplicación desplegada

```

---

## 📁 Archivos Creados

### 1. **.github/workflows/terraform-deploy.yml**

**Propósito**: Desplegar infraestructura con Terraform

**Pasos**:
1. Checkout del código
2. Setup Terraform
3. Validar sintaxis
4. Terraform Plan
5. Terraform Apply (solo en main)
6. Obtener outputs

**Se ejecuta cuando**:
- Push a `main` con cambios en `main.tf`
- Workflow manual (`workflow_dispatch`)

---

### 2. **.github/workflows/deploy.yml**

**Propósito**: Desplegar Docker en instancias EC2

**Pasos**:
1. **build-and-push**: Compila y sube imagen a Docker Hub
2. **get-instances**: Obtiene IDs de instancias del ASG
3. **deploy-to-instances**: Usa SSM para ejecutar `docker pull && docker run`
4. **verify-deployment**: Verifica que la app está respondiendo

**Se ejecuta cuando**:
- Push a `main/develop` con cambios en `dockerfile/index.html`
- Workflow manual

---

### 3. **deploy-to-instances.sh**

Script de utilidad para despliegues manuales desde terminal:

```bash
./deploy-to-instances.sh 'i-123456 i-789012' 'usuario/imagen:tag' 'us-east-1'
```

---

## 🔐 Requisitos en GitHub Secrets

Para que los workflows funcionen, necesitas estos secretos:

```
DOCKER_USERNAME          → Tu usuario de Docker Hub
DOCKER_PASSWORD          → Tu token de Docker Hub
AWS_ROLE_ARN            → ARN del role IAM con permisos:
                          - EC2
                          - SSM
                          - ELB
                          - AutoScaling
```

---

## 🏗️ Arquitectura Final

```
                        GITHUB REPOSITORY
                              │
                    ┌─────────┴─────────┐
                    │                   │
            ┌───────▼────────┐  ┌──────▼──────────┐
            │  main.tf changes│  │dockerfile/HTML │
            │   (uncommon)    │  │   (frequent)   │
            └───────┬────────┘  └──────┬──────────┘
                    │                   │
        ┌───────────▼──┐      ┌────────▼─────────┐
        │terraform-    │      │deploy.yml        │
        │deploy.yml    │      │(GitHub Actions)  │
        └───────┬──────┘      └────────┬─────────┘
                │                     │
        ┌──────▼──────────┐    ┌─────▼────────────┐
        │ Terraform       │    │Docker Build      │
        │ ├─ Init         │    │├─ Build image   │
        │ ├─ Plan         │    │├─ Push to Hub   │
        │ └─ Apply        │    │└─ Get SSM targets
        └──────┬──────────┘    └─────┬────────────┘
               │                     │
        ┌──────▼──────────┐    ┌─────▼─────────────┐
        │ AWS Resources   │    │AWS Systems Manager│
        │ ├─ VPC          │    │├─ Send commands  │
        │ ├─ ALB          │    │├─ docker pull    │
        │ ├─ ASG          │    │└─ docker run     │
        │ └─ EC2 (2)      │    └─────┬─────────────┘
        └─────────────────┘          │
                │                    │
                └────────┬───────────┘
                         │
                    ┌────▼─────────┐
                    │ RUNNING APP  │
                    │ ├─ ALB       │
                    │ └─ 2 Containers
                    └──────────────┘
```

---

## 🚀 Flujo Completo Paso a Paso

### Primera vez: Desplegar infraestructura

```bash
1. git push origin main (con cambios en main.tf)
   ↓
2. GitHub Actions: terraform-deploy.yml inicia
   ├─ terraform init
   ├─ terraform plan
   └─ terraform apply
   ↓
3. Se crea:
   ├─ VPC
   ├─ ALB (DNS: terraform-asg-example-xxx.elb.amazonaws.com)
   ├─ ASG
   └─ 2 EC2 Instances (sin Docker aún)
   ↓
4. ✅ Infraestructura lista
```

### Segunda vez: Desplegar aplicación

```bash
1. git push origin main (con cambios en dockerfile/index.html)
   ↓
2. GitHub Actions: deploy.yml inicia
   ├─ Build Docker image
   ├─ Push a Docker Hub
   ├─ Get instance IDs from ASG
   └─ Send SSM commands:
       docker pull tu-usuario/hello-world1:latest
       docker rm -f app || true
       docker run -d --name app -p 80:80 tu-usuario/hello-world1:latest
   ↓
3. Cada instancia ejecuta:
   ├─ Descarga la imagen
   ├─ Elimina container anterior
   └─ Inicia nuevo container
   ↓
4. ✅ Aplicación desplegada (ALB distribuye tráfico)
```

---

## 🔧 Comandos Útiles

### Despliegue manual de Terraform

```bash
cd test
terraform init
terraform plan
terraform apply
terraform output        # Ver DNS del ALB
terraform destroy       # Destruir todo
```

### Despliegue manual de Docker

```bash
# Obtener IDs de instancias
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "terraform-asg-example" \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
  --output text

# Desplegar usando el script
./deploy-to-instances.sh 'i-xxx i-yyy' 'usuario/imagen:latest'

# O usar AWS CLI manualmente
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker pull tu-usuario/imagen:latest","docker rm -f app || true","docker run -d --name app -p 80:80 tu-usuario/imagen:latest"]' \
  --targets "Key=instanceids,Values=i-xxxxx" \
  --region us-east-1
```

---

## ✅ Ventajas de esta Arquitectura

✅ **Separación de responsabilidades**
   - Terraform: Solo crea infraestructura
   - GitHub Actions: Despliega aplicación

✅ **Despliegues independientes**
   - Cambiar app sin afectar infraestructura
   - Cambiar infraestructura sin afectar app

✅ **Automatización completa**
   - Git push = deployment automático
   - Uso de AWS Systems Manager (sin SSH público)

✅ **Seguro**
   - Sin credenciales en el código
   - Instancias en VPC por defecto
   - SSM comunicación encriptada

✅ **Escalable**
   - ASG maneja múltiples instancias
   - ALB distribuye carga
   - Deployment automático a nuevas instancias

---

## 📌 Notas Importantes

1. **Primero infraestructura, luego app**
   - Asegúrate que terraform-deploy.yml se ejecute primero
   - Las instancias deben existir antes de desplegar Docker

2. **AWS Systems Manager**
   - Las instancias necesitan la política `AmazonSSMManagedInstanceCore`
   - Automáticamente añadida por el IAM role en main.tf

3. **Docker Hub**
   - La imagen debe existir en Docker Hub
   - Se recomienda usar tags en lugar de `latest`

4. **ALB DNS**
   - Tarda 1-2 minutos en estar completamente ready
   - Health checks cada 30 segundos

---

## 🎯 Próximos Pasos

1. **Configurar secretos en GitHub**
   - DOCKER_USERNAME
   - DOCKER_PASSWORD
   - AWS_ROLE_ARN

2. **Primera ejecución**
   ```bash
   git push origin main
   # Espera a terraform-deploy.yml
   # Luego despliega tu app con un nuevo push
   ```

3. **Monitoreo**
   - GitHub Actions > Actions > Ver logs
   - AWS Console > EC2 > Instances > Ver estado
   - Visita ALB DNS en navegador

---

**¡Listo para producción!** 🚀
