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

## 🤖 Week 36 — CI/CD pipeline and a custom script (K4, F3)

### 1️⃣ How the pipeline is built, and why deploy waits for build

The pipeline lives at `.github/workflows/deploy.yml` and has two jobs:

```
build  →  checkout, set up .NET, build, run tests, publish, upload artifact
deploy →  needs: build → download artifact, deploy to App Service, run health check
```

The `deploy` job has `needs: build`. Without that line the two jobs would start in parallel, on two separate empty runners that share nothing — and broken code could reach Azure at the same time the tests are still running. `needs: build` is the single line that turns two independent jobs into a safe sequence: if any step in `build` fails (especially the tests), `deploy` never starts, and the app in Azure keeps running the last working version.

The pipeline triggers on `push` to `main` (excluding `**.md` changes, so editing this file alone doesn't burn a deployment) and on `workflow_dispatch` for manual runs.

### 2️⃣ Deployment strategy (K4)

What the pipeline actually does is a simple **in-place deployment**: the new package is uploaded and the app is restarted on its instances. This is **not** rolling update, blue-green, or canary — all three require traffic control (splitting traffic between old and new versions), and this pipeline doesn't do that.

In practice no downtime was visible during testing: App Service keeps the old version answering until the new one has started and responds — a side effect of the platform, not a chosen strategy. That's an important distinction: it *looks* like blue-green, but there's no traffic control, no ability to choose *when* the swap happens, and no one-click rollback the way a real blue-green setup (Azure deployment slots) would give.

For an app with a handful of users, this in-place approach is perfectly reasonable — the cost of downtime is low, and the added complexity of rolling update (which needs multiple instances) or blue-green (which needs the S1 tier or higher, not available on B1/Basic) isn't justified yet.

### 3️⃣ Authentication — why the secret isn't in the code

Deploying to Azure requires proving GitHub Actions has permission to do so. The chain:

1. **Basic auth** was enabled once on the App Service (`basicPublishingCredentialsPolicies`, off by default for security).
2. A **publish profile** (a per-app username/password, not the main Azure account) was downloaded from the terminal.
3. It was piped straight into a **GitHub Secret** (`AZURE_WEBAPP_PUBLISH_PROFILE`) — never saved to a local file, note, or committed anywhere.
4. The workflow references it as `${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}` — GitHub decrypts it only at run time and masks it in all logs.

This follows the principle of least privilege: the profile only grants deploy access to this one app, not the whole Azure subscription. If it were ever compromised, the blast radius is limited to `app-clo25-rayan`.

`SCM_DO_BUILD_DURING_DEPLOYMENT` was also explicitly set to `false` — the pipeline already builds and publishes a ready package, so Azure shouldn't try to build it again. Making that explicit (rather than relying on the default) means the next reader doesn't have to guess whether it was intentional.

### 4️⃣ What the script does, beyond the pipeline's green checkmark (F3)

`scripts/health-check.sh` is a **smoke test**: after deployment, it pings `/health` in a loop (up to 10 attempts, 5 seconds apart) until it gets a `200`, or gives up and exits with code `1`.

Why this matters: a green checkmark in GitHub Actions only proves the *files* arrived — not that the app actually started. If the new version crashes on boot, the pipeline can still show green while the app is down. The script closes that gap by actually asking the app if it's alive.

The number of attempts is a second, optional argument (`./scripts/health-check.sh <url> [attempts]`), defaulting to 10 — tested locally both for success (`exit 0`) and failure against a non-existent path (`exit 1`, after 2 attempts to keep the test fast).

**Known limitation, noted honestly:** the health check can pass while the *old* version is still the one answering — App Service keeps serving the previous version until the new one is ready, so an early "OK" doesn't prove the new code is live. A more precise version would have `/health` report which version is currently running.

### 5️⃣ How to rebuild everything from scratch

Since the resource group is deleted after every lesson day, here's the exact sequence to bring the app back from nothing:

```bash
# 1. Resource group + plan + app + first deploy
az group create --name rg-clo25-rayan --location swedencentral

az webapp up \
  --name app-clo25-rayan \
  --resource-group rg-clo25-rayan \
  --runtime "DOTNETCORE:10.0" \
  --sku B1 \
  --location swedencentral \
  --os-type linux

# 2. Scale out to 3 instances
az appservice plan update \
  --name hamedmonfared85_asp_7506 \
  --resource-group rg-clo25-rayan \
  --number-of-workers 3

# 3. Health check path
az webapp config set \
  --resource-group rg-clo25-rayan \
  --name app-clo25-rayan \
  --generic-configurations health_check_path="/health"

# 4. Re-enable basic auth (needed before the publish profile works)
az resource update \
  --resource-group rg-clo25-rayan \
  --namespace Microsoft.Web \
  --resource-type basicPublishingCredentialsPolicies \
  --name scm \
  --parent sites/app-clo25-rayan \
  --set properties.allow=true

# 5. Get the (new) publish profile and set it as a GitHub secret directly —
#    never save it to a local file or note
az webapp deployment list-publishing-profiles \
  --name app-clo25-rayan \
  --resource-group rg-clo25-rayan \
  --xml | gh secret set AZURE_WEBAPP_PUBLISH_PROFILE

# 6. Tell Azure not to build the package itself
az webapp config appsettings set \
  --resource-group rg-clo25-rayan \
  --name app-clo25-rayan \
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false
```

After this, a plain `git push` to `main` builds, tests, deploys, and health-checks the app automatically — no manual `az webapp deploy` needed.

**Important:** the publish profile is tied to this specific app instance. Every time the resource group is rebuilt, step 5 must be repeated — the old secret becomes invalid the moment the old app is deleted.

---

## 📝 Alternatives I considered

- **App idea:** a to-do API or weather-proxy would also have worked, but a link shortener gives a clearer justification for a shared database/cache later in the course.
- **Deployment:** `az webapp up` was chosen over three separate commands (`plan create` / `webapp create` / `webapp deploy`) for simplicity at an early stage of the project — same underlying mechanism, fewer steps to keep track of.