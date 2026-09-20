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

## 🏗️ Week 37 — Infrastructure as Code with Bicep (K1, K2, F2, Komp1)

### 1️⃣ Which resources the template creates, and why (K1)

`infra/main.bicep` describes exactly two resources, matching what already existed from the manual setup in weeks 35–36:

- **`Microsoft.Web/serverfarms`** (the App Service Plan) — the machines the app runs on
- **`Microsoft.Web/sites`** (the Web App) — the app itself, pointing at the plan via `serverFarmId: plan.id`

No more, no fewer: a database, a Key Vault, or a Container Registry aren't needed yet for this track, so they aren't in the template. Adding resources "just in case" would make the file lie about what the solution actually depends on.

`planName` and `appName` are required parameters with **no default value** — on purpose. This template is meant to describe the plan and app that already exist, not invent new ones. A default would risk silently creating a second, differently-named app instead of updating the real one.

### 2️⃣ How scaling is defined, and why that value (K2)

```bicep
@minValue(1)
@maxValue(3)
param instanceCount int = 3

sku: {
  name: skuName
  capacity: instanceCount
}
```

`instanceCount` defaults to `3` — the same number chosen back in week 35, for the same reason: small enough to stay cheap on the B1 tier, large enough to prove the principle of redundancy and load balancing across multiple machines. The `@minValue`/`@maxValue` decorators encode the same reasoning as code: this template should never accidentally scale below 1 (no redundancy) or above what B1 can reasonably support.

### 3️⃣ What in the template is security (K2)

```bicep
httpsOnly: true
siteConfig: {
  minTlsVersion: '1.3'
  healthCheckPath: healthCheckPath
  alwaysOn: true
}
```

- **`httpsOnly: true`** — refuses plain HTTP, matching the automatic HTTPS App Service already provides on `azurewebsites.net`
- **`minTlsVersion: '1.3'`** — the `what-if` preview showed this as an actual change (the manually-created app was still on the `1.2` default); the template now enforces the stricter version as code, not as a one-off setting someone might forget to repeat
- **`healthCheckPath: '/health'`** — the same health check from week 35, now version-controlled instead of a manual click
- **`SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'`** (as an app setting) — makes explicit, in code, that Azure should never try to build the package itself

Secrets themselves are **not** in this file — the deployment identity (see below) is a service principal stored as a GitHub secret (`AZURE_CREDENTIALS`), never hardcoded in the template or committed to the repo.

### 4️⃣ How infrastructure is deployed, why, and what the next step would be (F2, Komp1)

**Chosen approach: Plan A.** A service principal (`sp-clo25-rayan`) was created with the `Contributor` role, scoped only to `rg-clo25-rayan` — not the whole subscription:

```bash
az ad sp create-for-rbac --name sp-clo25-rayan --role Contributor \
  --scopes /subscriptions/<id>/resourceGroups/rg-clo25-rayan \
  --json-auth > azure-credentials.json
```

The resulting JSON was piped straight into a GitHub secret (`AZURE_CREDENTIALS`) and the local file deleted immediately — the same pattern used for the publish profile in week 36.

**Why a narrow scope matters (least privilege):** a leaked publish profile can only overwrite one app. A leaked credential with `Contributor` on the whole subscription could create or delete *anything*, anywhere in the account. The cost of that narrow scope: the role assignment is a child of the resource group and is deleted along with it — the underlying Entra ID identity survives, but the *permission* doesn't. Every time the resource group is rebuilt, the service principal must be re-granted access, or the pipeline fails with `AuthorizationFailed`. That's not a bug — it's the price of least privilege, paid deliberately.

**`az bicep build` and `what-if` before every deploy:** the template was compiled locally first to catch syntax errors early, and `what-if` was run before every real deployment. Reading a `what-if` diff means trusting only the *resource-level* lines (`~`, `+`, `-` next to a resource name like `Microsoft.Web/sites/...`) — the indented property-level noise (`freeOfferExpirationTime`, `netFrameworkVersion`) is safe to ignore, since it reflects fields Azure fills in that this template doesn't manage.

**Verified idempotence:** running the same deployment twice showed the plan settle to `= Nochange` on the second run, while the app still showed harmless noise — confirming the deployment is idempotent even though `what-if`'s *prediction* isn't perfectly clean.

**Own script:** `scripts/deploy-infra.sh` wraps both `what-if` (preview, `--what-if` as the first argument) and the real deploy in one script, so the same command works locally and could be wired into the pipeline later.

**What the next step would be:** currently this Bicep deployment is run manually from the terminal (Plan A's script exists, but there is no dedicated `infra` job in `deploy.yml` yet). The natural next step is adding that job — using `azure/login` with the `AZURE_CREDENTIALS` secret, running `deploy-infra.sh` before the `deploy` job, and adding `needs: [build, infra]` so the app is never deployed against infrastructure that failed to provision. A further step beyond that (mentioned in the course material for week 40) would be replacing the stored service principal secret with OIDC — an identity with no long-lived password to leak in the first place.

---

## 🐳 Week 38 — Containers, ACR, and Container Apps (F1, K1, K2, K4, Komp1)

### 1️⃣ Container track structure, and why Container Apps (F1, K1)

The app now runs two completely independent ways from the same repo: the existing App Service track (weeks 35–37), and a new container track — a multi-stage `Dockerfile` (`src/BeaconSalami/Dockerfile`), built into an image in a private Azure Container Registry (`acrclo25rayan`), running on Azure Container Apps (`ca-clo25-rayan`).

Container Apps was chosen over plain "Container Instances" or self-managed Kubernetes because it gives HTTP-based autoscaling (including scale-to-zero) and managed revisions out of the box, without having to operate a cluster. For a course project whose point is demonstrating scalability concepts rather than running a large production workload, that's the right level of abstraction — all the scaling behaviour F1/K2 ask for, none of the operational overhead of AKS.

The Dockerfile itself is a standard two-stage build: an SDK image compiles and publishes the app, and only the published output is copied into a much smaller ASP.NET runtime image. The final image never carries the full SDK, which keeps it smaller and reduces its attack surface.

Docker wasn't installed locally, so the entire build-and-run cycle used `az acr build` instead of a local `docker build` — Azure builds and pushes the image directly in the registry. This has a side benefit worth noting: the image is always built inside a Linux environment that matches the real deployment target exactly, removing any "works on my machine" risk from a different local OS.

### 2️⃣ How scaling is defined, and why these values (K2)

```bicep
minReplicas: 0
maxReplicas: 3
rules: [
  {
    name: 'http-scale-rule'
    http: {
      metadata: {
        concurrentRequests: '10'
      }
    }
  }
]
```

- **`minReplicas: 0`** — scale-to-zero. Unlike the App Service track (always-on, `alwaysOn: true`), a demo app with no real traffic doesn't need to run continuously here; this is a deliberate contrast between the two tracks, not an oversight.
- **`maxReplicas: 3`** — kept in line with the `instanceCount` ceiling chosen for App Service in week 35, for the same underlying reason: enough to prove horizontal scaling under load, capped low enough to bound cost if something misbehaves.
- **`concurrentRequests: 10`** — the HTTP scale rule's threshold: once a replica is handling more than 10 concurrent requests, Container Apps starts another replica. A low number was chosen on purpose, since the app itself is lightweight (an in-memory dictionary, no real backend work per request) — it should scale out early rather than let one replica queue up requests.

### 3️⃣ Registry authentication — both directions (K2, Komp1)

Two separate authentication problems had to be solved, in opposite directions:

**Pushing an image into the registry (CI/CD → ACR).** The GitHub Actions pipeline authenticates as the same `sp-clo25-rayan` service principal used for Bicep deployments (Plan A, `AZURE_CREDENTIALS` secret), via `azure/login@v2`. Once logged in, `az acr build` both builds *and* pushes under that identity — no separate registry credential is needed for this direction, since the service principal's `Contributor` role on the resource group already covers ACR.

**Pulling an image out of the registry (Container Apps → ACR).** This is a completely different identity: the Container App itself needs credentials to pull the image at startup, independent of whoever pushed it. `container.bicep` solves this with the registry's admin credentials (`adminUserEnabled: true`, then `acr.listCredentials()`), stored as a Container Apps *secret* (`acr-password`) rather than a plain property — so the password never appears in cleartext in the template or its outputs.

The two directions use different mechanisms (a logged-in CLI identity vs. a stored registry secret) because they run in different contexts: one is an ephemeral GitHub Actions runner, the other is a long-lived Azure resource that needs to authenticate every time it restarts a replica, with nothing interactive available to log in with.

**A concrete failure worth documenting:** the same lesson from week 37 repeated itself here. Deleting and recreating the resource group also deletes the service principal's *role assignment* on it (the identity survives in Entra ID, but the permission is a child of the resource group). The very first run of `deploy-container.yml` failed at the `azure/login` step with "No subscriptions found" for exactly this reason — the role assignment had to be recreated (`az role assignment create`) before the pipeline could authenticate again. This is now a standard part of restarting the project each session, for both tracks.

### 4️⃣ Deployment strategy — revisions (K4)

Container Apps uses **revisions** as its deployment mechanism: every time the pipeline calls `az containerapp update --image ...:${{ github.sha }}`, a brand-new revision is created and traffic is switched to it — verified directly:

```
Rev                      Active
-----------------------  --------
ca-clo25-rayan--i2jtoq5  False
ca-clo25-rayan--0000001  True
```

The old revision is not deleted — it's simply marked inactive, which is what makes rollback possible (pointing traffic back at a previous revision) without rebuilding anything. This is conceptually the container-track equivalent of the App Service track's in-place update, but structurally closer to a blue-green deploy: unlike an in-place update, the previous version's container is still sitting there, not overwritten, until it's explicitly cleaned up.

Tagging every image with `${{ github.sha }}` (in addition to `:latest`) is what makes this work — Container Apps only creates a new revision when the image reference actually changes, so reusing `:latest` alone would silently update the app to newer contents without a traceable, unique tag per deploy.

### 5️⃣ Same app, two tracks — what's shared

Both tracks run the exact same `Program.cs` — same endpoints, same in-memory `ConcurrentDictionary` store, same `/health` check. Nothing in the application code is container-specific or App-Service-specific. What differs is entirely at the infrastructure layer: how the app is packaged (a zip vs. a container image), how it's hosted (App Service Plan vs. Container Apps Environment), and how it scales (instance count vs. HTTP-based replica scaling with scale-to-zero).

The one thing genuinely *not* shared between the tracks is state: each track's replicas hold their own separate in-memory dictionary, so a link shortened on the App Service track doesn't resolve on the Container Apps track, and vice versa. That's the same known limitation flagged since week 34 — solving it (a shared store such as Azure Cache for Redis or a database) is the natural next step for whichever track continues past this course.

---

## 📝 Alternatives I considered

- **App idea:** a to-do API or weather-proxy would also have worked, but a link shortener gives a clearer justification for a shared database/cache later in the course.
- **Deployment (week 35):** `az webapp up` was chosen over three separate commands (`plan create` / `webapp create` / `webapp deploy`) for simplicity at an early stage of the project — same underlying mechanism, fewer steps to keep track of.
- **IaC tool (week 37):** Bicep was chosen over Terraform and ARM. Terraform's main advantage — supporting multiple clouds — isn't relevant here since this project only targets Azure. ARM uses the same underlying engine as Bicep but is written directly in JSON, which is considerably harder to read and write by hand. Bicep gives the same declarative guarantees with the easiest syntax to get started with for an Azure-only project.
- **Infra deployment location (week 37):** running Bicep from the terminal (Plan A's script, executed manually) was chosen for now over adding a dedicated `infra` job inside the CI/CD pipeline. Both use the same files in the repo — the difference is only who presses the button. Automating it fully is the natural next step, noted above.
- **Local container builds (week 38):** `az acr build` was chosen over a local `docker build` since Docker wasn't installed locally. Beyond being the only viable option at the time, it turned out to have a real advantage: the image is always built in the same Linux environment it will run in, removing any risk of a Windows-vs-Linux mismatch that a local build could have introduced.