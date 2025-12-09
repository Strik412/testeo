# ✅ RESUMEN FINAL: Terraform + GitHub Actions

## 📁 Archivos del Proyecto

```
test/
├── main.tf                                 ← Infraestructura (VPC, ALB, ASG, EC2)
├── dockerfile                              ← Tu aplicación
├── index.html                              ← Tu aplicación
├── deploy-to-instances.sh                  ← Script helper (opcional)
│
├── .github/workflows/
│   ├── terraform-deploy.yml                ← Deploy infraestructura
│   └── deploy.yml                          ← Deploy aplicación Docker
│
└── GITHUB_ACTIONS_GUIDE.md                 ← Esta guía
```

---

## 🔄 Flujo de Trabajo

### **Escenario 1: Primero Desplegar Infraestructura**

```
1. git push origin main (cambios en main.tf)
   ↓
2. terraform-deploy.yml se ejecuta
   ├─ terraform init
   ├─ terraform plan
   └─ terraform apply
   ↓
3. Se crea en AWS:
   ├─ VPC
   ├─ Security Groups
   ├─ ALB (terraform-asg-example-xxx.elb.amazonaws.com)
   ├─ Target Group
   └─ ASG con 2 EC2 instances (Docker instalado, esperando app)
   ↓
4. ✅ Infraestructura lista (sin aplicación aún)
```

### **Escenario 2: Luego Desplegar Aplicación**

```
1. git push origin main (cambios en dockerfile/index.html)
   ↓
2. deploy.yml se ejecuta
   ├─ Build Docker image
   ├─ Push a Docker Hub
   ├─ Get EC2 instance IDs from ASG
   └─ For each instance:
       • aws ssm send-command
       • docker pull tu-usuario/hello-world1:latest
       • docker run -d --name app -p 80:80 tu-usuario/hello-world1:latest
   ↓
3. Cada instancia:
   ├─ Descarga imagen Docker
   ├─ Elimina container anterior
   └─ Inicia nuevo container
   ↓
4. ALB distribuye tráfico entre instancias
   ↓
5. ✅ Aplicación desplegada y accesible
```

### **Escenario 3: Solo Cambiar Aplicación (Más Frecuente)**

```
Cambiar código → Push → GitHub Actions Deploy → Instancias actualizadas
(sin tocar infraestructura)
```

---

## 📊 Componentes de main.tf

| Componente | Función | Modificado |
|-----------|---------|-----------|
| `terraform` block | Versión y providers | ❌ No |
| `provider "aws"` | Región (us-east-1) | ❌ No |
| Data sources | VPC, subnets, AMI | ❌ No |
| Security Groups | Firewall rules | ❌ No |
| **IAM Role** | **SSM permisos** | ✅ **Sí** |
| **Instance Profile** | **Para el role** | ✅ **Sí** |
| ALB | Load balancer | ❌ No |
| Target Group | Health checks | ❌ No |
| Listener | Puerto 80 | ❌ No |
| Launch Template | **Sin Docker** | ✅ **Sí** |
| ASG | Auto scaling | ❌ No |
| **Outputs** | **Nuevo: instance_ids** | ✅ **Sí** |

---

## 🔑 Cambios en main.tf

### ❌ Removido: Docker pull y run

```terraform
# ANTES (ya no existe):
docker pull dapaeza/hello-world1
docker run -d --name app -p 80:80 dapaeza/hello-world1
```

### ✅ Añadido: IAM Role para SSM

```terraform
resource "aws_iam_role" "ec2_role" {
  # Permite que EC2 use AWS Systems Manager
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  # Adjunta política AmazonSSMManagedInstanceCore
}

resource "aws_iam_instance_profile" "ec2_profile" {
  # Para usar el role
}
```

### ✅ Añadido: Instance Profile al Launch Template

```terraform
iam_instance_profile {
  name = aws_iam_instance_profile.ec2_profile.name
}
```

### ✅ Añadido: Nuevos Outputs

```terraform
output "instance_ids" {
  # Para que GitHub Actions sepa a qué instancias desplegar
}

output "asg_name" {
  # Para identificar el ASG
}
```

---

## 🤖 Workflows de GitHub Actions

### **terraform-deploy.yml** (Infraestructura)

```yaml
name: Terraform Deploy Infrastructure

Triggers:
  - Push a main con cambios en main.tf
  - Manual workflow_dispatch

Jobs:
  ├─ terraform-plan
  │  └─ Validar y planificar
  │
  └─ terraform-apply (solo main)
     └─ Crear/actualizar infraestructura
```

### **deploy.yml** (Aplicación Docker)

```yaml
name: Deploy Docker to EC2 Instances

Triggers:
  - Push a main/develop con cambios en dockerfile/index.html
  - Manual workflow_dispatch

Jobs:
  ├─ build-and-push
  │  └─ Compilar y subir imagen Docker Hub
  │
  ├─ get-instances
  │  └─ Obtener IDs de instancias del ASG
  │
  ├─ deploy-to-instances
  │  └─ SSM: docker pull && docker run
  │
  └─ verify-deployment
     └─ Comprobar que la app responde
```

---

## 🔐 GitHub Secrets Requeridos

Para que los workflows funcionen, necesitas en tu repositorio:

**Settings > Secrets and variables > Actions**

```
DOCKER_USERNAME       Tu usuario de Docker Hub
DOCKER_PASSWORD       Tu token de Docker Hub
AWS_ROLE_ARN         arn:aws:iam::ACCOUNT:role/github-actions-role
```

---

## 📋 Checklist de Configuración

- [ ] Repositorio creado en GitHub
- [ ] Clonado localmente
- [ ] Archivos: main.tf, dockerfile, index.html
- [ ] Workflows creados en .github/workflows/
- [ ] Docker imagen subida a Docker Hub
- [ ] Secretos configurados en GitHub
- [ ] AWS IAM role creado para GitHub Actions
- [ ] Push a main para iniciar despliegue

---

## 🚀 Inicio Rápido

### 1. Primera vez: Crear infraestructura

```bash
cd test
git add .
git commit -m "Infrastructure setup"
git push origin main

# Espera a que terraform-deploy.yml se complete
# Verifica en GitHub > Actions > Terraform Deploy Infrastructure
```

### 2. Segunda vez: Desplegar aplicación

```bash
# Edita tu dockerfile o index.html

git add dockerfile index.html
git commit -m "App update"
git push origin main

# deploy.yml se ejecuta automáticamente
# Verifica en GitHub > Actions > Deploy Docker to EC2 Instances
```

### 3. Ver tu aplicación

```bash
# Obtener DNS del ALB
terraform output alb_dns_name

# Abrir en navegador
# http://terraform-asg-example-xxx.elb.amazonaws.com
```

---

## 📊 Ventajas

✅ **Infraestructura y App Desacopladas**
   - Cambiar app sin rehacer infraestructura
   - Escalar sin redeploy de código

✅ **Automatización Total**
   - Git push = deployment automático
   - Sin intervención manual

✅ **Seguridad**
   - Sin SSH público
   - AWS Systems Manager encriptado
   - Credenciales en GitHub Secrets

✅ **Flexibilidad**
   - Deploy manual si necesitas
   - Scripts auxiliares disponibles

✅ **Observabilidad**
   - Logs de GitHub Actions
   - Logs de AWS CloudWatch
   - Outputs de Terraform

---

## 🐛 Troubleshooting

### terraform-deploy.yml falla

**Causa**: Credenciales AWS o sintaxis Terraform
**Solución**: Revisa logs en GitHub > Actions

### deploy.yml no encuentra instancias

**Causa**: ASG aún no tiene instancias running
**Solución**: Espera a que terraform-deploy.yml complete

### Instancias no responden a SSM

**Causa**: Falta IAM role o permisos
**Solución**: Verifica que main.tf incluye IAM role correctamente

### ALB responde pero sin aplicación

**Causa**: deploy.yml no se ha ejecutado
**Solución**: Push cambios en dockerfile/index.html

---

## 📖 Archivos de Referencia

- **main.tf** → Infraestructura completa
- **.github/workflows/terraform-deploy.yml** → Deploy infra
- **.github/workflows/deploy.yml** → Deploy app
- **GITHUB_ACTIONS_GUIDE.md** → Documentación detallada

---

## 🎯 Próximos Pasos

1. ✅ Configurar secretos
2. ✅ Push a main
3. ✅ Monitorear workflows
4. ✅ Acceder a aplicación
5. 🔄 Hacer cambios y re-desplegar

---

**¡Listo para producción!** 🚀
