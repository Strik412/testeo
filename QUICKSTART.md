# ⚡ Guía Rápida (5 minutos)

## 🎯 Tu flujo

1. **Terraform** (local) → Crea infraestructura AWS
2. **GitHub Actions** (automático) → Despliega Docker cuando haces push

---

## 🚀 En 6 pasos

### 1️⃣ Ejecutar Terraform (5-10 minutos)
```bash
terraform init
terraform apply
```

### 2️⃣ Guardar la Private Key SSH
```bash
terraform output -raw private_key > deployer_key.pem
```

### 3️⃣ Ver los outputs (anótalos)
```bash
terraform output
```

Anota:
- `alb_dns_name`
- `instance_ips` (separadas por espacio: "10.0.1.100 10.0.2.200")

### 4️⃣ Configurar GitHub Secrets
En tu repo: Settings → Secrets and variables → Actions

Agrega:
- `DOCKER_USERNAME` → Tu Docker Hub username
- `DOCKER_PASSWORD` → Tu Docker Hub token
- `SSH_PRIVATE_KEY` → Contenido del `deployer_key.pem` (cat deployer_key.pem)
- `INSTANCE_IPS` → Las IPs privadas (Ej: "10.0.1.100 10.0.2.200")
- `ALB_DNS` → El DNS del ALB (Ej: "terraform-asg-example-xxx.elb.amazonaws.com")

### 5️⃣ Hacer push a GitHub
```bash
git add .
git commit -m "Add Terraform + Docker deploy"
git push origin main
```

### 6️⃣ Cada cambio → Auto-deploy
```bash
# Edita dockerfile o index.html
git add .
git commit -m "Update app"
git push origin main
# GitHub Actions automáticamente:
# 1. Build Docker image
# 2. Push a Docker Hub
# 3. SSH deploy a instancias
# 4. Verifica que funciona
```

---

## 📊 ¿Qué hace cada componente?

| Componente | Responsable | Cuándo se ejecuta |
|------------|-------------|-------------------|
| **main.tf** | Tú (local) | Una sola vez (terraform apply) |
| **dockerfile** | GitHub Actions | Cada vez que haces push |
| **index.html** | GitHub Actions | Cada vez que haces push |
| **deploy.yml** | GitHub Actions | Automático (SSH deploy) |

---

## 🔍 Ver logs de GitHub Actions

1. Ve a tu repo en GitHub
2. Click en "Actions" tab
3. Selecciona el workflow "Deploy Docker to EC2 Instances"
4. Haz click en el run más reciente

---

## ❌ Troubleshooting rápido

| Problema | Solución |
|----------|----------|
| "Permission denied (publickey)" | Verifica que `SSH_PRIVATE_KEY` es exacto |
| "Cannot pull image" | Verifica `DOCKER_USERNAME` y `DOCKER_PASSWORD` |
| ALB no responde | Espera 3-5 minutos, luego intenta |
| "No such host" en SSH | Las `INSTANCE_IPS` deben ser privadas (10.0.x.x) |

---

## ✅ Verificar que funciona

```bash
# Ver estado de instancias en AWS CLI
aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,State.Name]" --output table

# Conectar por SSH (manual)
ssh -i deployer_key.pem ec2-user@10.0.1.100

# Ver logs del container
docker logs app

# Ver si Docker está corriendo
docker ps
```

---

## 📚 Para más detalles
→ Lee `SETUP.md` para explicación completa

---


