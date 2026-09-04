# 🧭 TUTORIAL.md — BeaconSalami

A step-by-step documentation of how BeaconSalami (my link shortener) was built, week by week, for the course **Skalbara molnapplikationer** (Scalable Cloud Applications).

This document is updated every week as new layers are added (app → to the cloud → automatic deployment → infrastructure as code → container → security).

---

## 📦 Week 34 — The base app

### What was built
- A new .NET web project (`src/BeaconSalami`) with a matching test project (`tests/BeaconSalami.Tests`)
- A `/` endpoint returning the app's name and status
- A `/health` endpoint returning `200 OK`
- Git repo initialized and pushed to GitHub, set to public

### App idea
I chose a **link shortener** as my app idea, one of the examples mentioned in the course material (alongside a to-do API, weather-proxy, and quote API). It's small (few endpoints), but naturally motivates a shared database and caching later on (week 39), while still being easy to keep stateless.

### Why `/health` exists from the start
`/health` is later used by App Service (week 35), by my own script (week 36), and by the container (week 38). It was built in from day one so nothing had to change afterward.

---

## ☁️ Week 35 — App Service, scaling, and health check (K2)

### 🎯 What this section proves
According to the assignment criteria, **K2** requires that the solution has *scaling and load balancing in place*, and that I can explain it. This section is that proof.

### Resources created

| Resource | Name |
|---|---|
| Resource group | `rg-clo25-rayan` |
| App Service Plan | `hamedmonfared85_asp_7506` |
| Web App | `app-clo25-rayan` |
| Tier | **B1 (Basic)** |
| Number of instances | **3** |
| Health check path | `/health` |

### How the app was deployed
Instead of running `az appservice plan create`, `az webapp create`, and `az webapp deploy` as three separate commands, the combined command was used:

```bash
az webapp up \
  --name app-clo25-rayan \
  --resource-group rg-clo25-rayan \
  --runtime "DOTNETCORE:10.0" \
  --sku B1 \
  --location swedencentral \
  --os-type linux
```

`az webapp up` creates the resource group (if missing), the plan, the app, and packages/uploads the code in a single step. The underlying mechanism is the same as the manual route (publish → zip → deploy) — just hidden. I chose this route for speed early in the project.

### 🔢 Why B1?
B1 (Basic) is the cheapest tier that allows **more than one instance**. The Free tier does not allow scaling out to multiple instances, which makes B1 the lowest tier that satisfies K2.

### 🔁 Why 3 instances?
Three is a small but clear number — enough to prove the principle (redundancy + load balancing across multiple machines) without the cost of a larger setup. The point isn't the number itself, but being able to justify it.

Verified with:
```bash
az appservice plan list \
  --resource-group rg-clo25-rayan \
  --query "[].{Name:name, Tier:sku.name, Instances:sku.capacity}" \
  --output table
```
→ `Instances: 3` confirmed, up from `1` before scaling.

### 🩺 Health check
Enabled with:
```bash
az webapp config set \
  --resource-group rg-clo25-rayan \
  --name app-clo25-rayan \
  --generic-configurations health_check_path="/health"
```
Verified with `az webapp show ... --query siteConfig.healthCheckPath` → returned `/health`.

App Service now pings `/health` regularly. If an instance stops responding there, it's automatically taken out of the traffic rotation — no custom failover logic was needed, which is the whole point of choosing PaaS.

### ⏱️ What I observed on restart
An `az webapp restart` was tested with all 3 instances active. It took roughly **10 seconds** before `/health` responded `200` again. This shows a manual restart is not a rolling update — all instances restarted at roughly the same time. Closing that gap to zero requires a deliberate deployment strategy (rolling update), which is exactly what week 36 covers.

### 🧹 Cost control
The resource group is torn down after every lesson day to avoid unnecessary cost:
```bash
az group delete --name rg-clo25-rayan --yes --no-wait
```
Verified with `az group exists --name rg-clo25-rayan` → `false`.

**Key lesson:** `az webapp stop` does *not* reduce cost — you pay for the App Service Plan (the machines), not for whether the app responds. That's why the whole resource group is deleted instead.

---

## 🚧 Week 36 — coming up

CI/CD pipeline, deployment strategy (K4), and a custom script (F3). To be filled in after lab 03.

---

## 📝 Alternatives I considered

- **App idea:** a to-do API or weather-proxy would also have worked, but a link shortener gives a clearer justification for a shared database/cache later in the course.
- **Deployment:** `az webapp up` was chosen over three separate commands (`plan create` / `webapp create` / `webapp deploy`) for simplicity at an early stage of the project — same underlying mechanism, fewer steps to keep track of.
