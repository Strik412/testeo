# 📋 Setup: Terraform Infrastructure + GitHub Actions Deployment

## 🎯 Arquitectura

```
┌─────────────────────────────────┐
│ TÚ (Ejecuta localmente)         │
│ terraform apply                 │
└────────────────┬────────────────┘
                 │
                 ▼
        ┌────────────────┐
        │ AWS Infrast.   │
        │ VPC + ALB      │
        │ ASG + EC2 x2   │
        │ (Docker ready) │
        └────────┬───────┘
                 │
    ┌────────────┴────────────┐
    │ GitHub Actions          │
    │ (Auto cuando push)      │
    ▼                         ▼
BUILD & PUSH          SSH DEPLOY
Docker Image          a las instancias
a Docker Hub          pull + run
```

---

## ✅ Paso 1: Preparar tu máquina

### 1.1 Instalar Terraform
```bash
# Windows: Descarga desde https://www.terraform.io/downloads
# O con chocolatey:
choco install terraform
```

### 1.2 Configurar credenciales AWS
```powershell
# En PowerShell
$env:AWS_ACCESS_KEY_ID = "tu_access_key"
$env:AWS_SECRET_ACCESS_KEY = "tu_secret_key"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

---

## ✅ Paso 2: Ejecutar Terraform

```bash
cd tu_repo/
terraform init
terraform plan
terraform apply
```

**Espera 5-10 minutos** a que se cree la infraestructura.

### Salida esperada:
```
Outputs:

alb_dns_name = "terraform-asg-example-xxx.elb.amazonaws.com"
asg_name = "terraform-asg-example"
instance_ids = ["i-xxx", "i-yyy"]
instance_ips = ["10.0.1.100", "10.0.2.200"]
```

---

## ✅ Paso 3: Obtener la Private Key SSH

Terraform ha generado una key SSH. Necesitas guardarla:

```bash
# En PowerShell
terraform output -raw private_key | Out-File deployer_key.pem -Encoding UTF8

# En bash/Linux/Mac
terraform output -raw private_key > deployer_key.pem
chmod 600 deployer_key.pem
```

---

## ✅ Paso 4: Configurar GitHub Secrets

Ve a tu repo en GitHub → Settings → Secrets and variables → Actions

Agrega estos 5 secretos:

| Secret | Valor | Dónde obtenerlo |
|--------|-------|-----------------|
| `DOCKER_USERNAME` | Tu usuario Docker Hub | https://hub.docker.com |
| `DOCKER_PASSWORD` | Token de Docker Hub | Docker Hub → Account Settings → Security |
| `SSH_PRIVATE_KEY` | Contenido del `deployer_key.pem` | `terraform output -raw private_key` |
| `INSTANCE_IPS` | IPs privadas (separadas por espacio) | `terraform output instance_ips` → Ej: "10.0.1.100 10.0.2.200" |
| `ALB_DNS` | DNS del ALB | `terraform output alb_dns_name` → Ej: "terraform-asg-example-xxx.elb.amazonaws.com" |

---

## ✅ Paso 5: Hacer Push a GitHub

```bash
git add .
git commit -m "Initial setup with Terraform + Docker deploy"
git push origin main
```

---

## ✅ Paso 6: Cada cambio en Docker → Auto-deploy

Modifica `dockerfile` o `index.html`:

```bash
# Edita un archivo
git add dockerfile index.html
git commit -m "Update Docker image"
git push origin main
```

**Automáticamente:**
1. ✅ GitHub Actions construye imagen Docker
2. ✅ La pushea a Docker Hub
3. ✅ Conecta por SSH a cada instancia
4. ✅ Ejecuta `docker pull` y `docker run`
5. ✅ Verifica que el ALB responda

---

## 📊 GitHub Actions Workflow: deploy.yml

### Job 1: build-and-push
- Construye la imagen Docker
- La pushea a Docker Hub (tag: `latest`)
- Usa Docker BuildKit para caché

### Job 2: deploy-to-instances
- Se conecta por SSH a cada instancia (usando private key)
- Espera a que Docker esté listo (máx 2 minutos)
- `docker pull usuario/imagen:latest`
- `docker rm -f app` (detiene el viejo)
- `docker run -d --name app -p 80:80 usuario/imagen:latest` (inicia)

### Job 3: verify-deployment
- Espera 15 segundos
- Intenta conectar al ALB (máx 30 intentos)
- Verifica que la app responda

---

## 🔧 Archivos principales

```
.
├── main.tf                          ← Infraestructura (TÚ ejecutas)
│   ├── VPC (default)
│   ├── Security Groups (HTTP + SSH)
│   ├── ALB + Target Group
│   ├── Launch Template (con Docker)
│   ├── ASG (min=1, max=3, desired=2)
│   ├── TLS Key Pair (para SSH)
│   └── Outputs (IPs, DNS, private key)
│
├── dockerfile                       ← Tu app (GitHub Actions construye)
├── index.html                       ← Tu app
│
└── .github/workflows/
    └── deploy.yml                   ← Auto-deploy por SSH
```

---

## 🚀 Flujo completo en 1 minuto

### Primer deploy (infraestructura):
```bash
terraform apply -auto-approve
# Espera 10 min
terraform output -raw private_key > deployer_key.pem
# Copia outputs a GitHub Secrets
git push origin main
```

### Deployments posteriores (solo app):
```bash
# Edita dockerfile o index.html
git add .
git commit -m "Update"
git push origin main
# GitHub Actions automáticamente:
# 1. Build Docker image
# 2. SSH a instancias
# 3. docker pull y docker run
# ✅ Hecho en ~5 minutos
```

---

## 🔍 Troubleshooting

### GitHub Actions falla en SSH
**Error:** "Permission denied (publickey)"
- ✅ Verifica que `SSH_PRIVATE_KEY` esté exacto
- ✅ Verifica que `INSTANCE_IPS` sean privadas (10.0.x.x)
- ✅ Revisa que el Security Group permite SSH (puerto 22)

### GitHub Actions falla en Docker push
**Error:** "authentication required"
- ✅ Verifica `DOCKER_USERNAME` y `DOCKER_PASSWORD` correctos
- ✅ Asegúrate de que el repositorio existe en Docker Hub

### ALB no responde
**Error:** "Connection refused"
- ✅ Espera 2-3 minutos a que Docker inicie
- ✅ Revisa logs: `docker logs app` en una instancia
- ✅ Verifica que el puerto 80 está abierto en el ALB

### No puedo conectar por SSH manualmente
```bash
ssh -i deployer_key.pem ec2-user@10.0.1.100
```
Si no funciona:
- ✅ Verifica que la instancia está en estado "running"
- ✅ Verifica que el Security Group permite puerto 22
- ✅ Intenta desde una máquina con Internet

---

## 📝 Resumen de cambios

**main.tf ahora:**
- ✅ Crea Key Pair automáticamente
- ✅ Abre puerto 22 para SSH
- ✅ Exporta IPs privadas y private key
- ✅ Instala solo Docker (no la app)

**deploy.yml ahora:**
- ✅ Construye imagen Docker
- ✅ Se conecta por SSH (no Systems Manager)
- ✅ Ejecuta deploy remoto
- ✅ Verifica que funciona

---

## 📞 Próximos pasos

1. Ejecuta `terraform apply`
2. Guarda la private key
3. Configura los 5 GitHub Secrets
4. Haz push y ve GitHub Actions en acción

¡Listo! 🎉
