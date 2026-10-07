# 🔗 BeaconSalami

A small link-shortener API, built as the semester project for the course **Skalbara molnapplikationer** (Scalable Cloud Applications).

The same app runs on Azure in **two ways**, so the two hosting models can be compared side by side:

| Track | Hosting | Scaling | Deployed by |
|---|---|---|---|
| **App Service** | Azure App Service, Linux, B1 | 3 instances, always on | `.github/workflows/deploy.yml` (publish profile) |
| **Container Apps** | Container image in Azure Container Registry, run on Azure Container Apps | 0 to 3 replicas, HTTP scale rule | `.github/workflows/deploy-container.yml` (OIDC, no stored password) |

Every week added a layer: app → cloud → automatic deployment → infrastructure as code → container → security. 👉 **Start with [`docs/TUTORIAL.md`](./docs/TUTORIAL.md)**: it has the week-by-week build log, the reasoning behind every decision, a complete *"From zero to running"* rebuild guide, and an honest list of known weaknesses.

---

## ✨ What it does

| Endpoint | Method | Description |
|---|---|---|
| `/` | `GET` | Returns app name and status |
| `/health` | `GET` | Health check, returns `200 OK` |
| `/shorten` | `POST` | Takes `{ "url": "..." }`, returns a short code |
| `/{code}` | `GET` | Redirects (`302`) to the original URL, or `404` if the code is unknown |
| `/instance` | `GET` | Shows which instance or replica answered and how many links it holds in memory |

Every response also carries an `X-Instance-Id` header with the name of the instance or replica that served it. It makes scaling visible: with several instances you can see *who* answered each request.

### Example

```bash
curl -X POST http://localhost:5001/shorten \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/a/very/long/path"}'
# → {"code":"1","shortUrl":"/1"}

curl -i http://localhost:5001/1
# → 302 Found, Location: https://example.com/a/very/long/path
```

---

## 🛠️ Tech stack

- **.NET 10** minimal API (C#), **xUnit** tests
- **Azure App Service** (Linux, B1) and **Azure Container Apps** + **Azure Container Registry**
- **Bicep** for infrastructure as code (`infra/`)
- **GitHub Actions** for CI/CD, with **OIDC** login to Azure for the container pipeline
- **Azure Key Vault** with a managed identity (proven end-to-end with a demo secret)

⚠️ **Known limitation:** storage is an in-memory `ConcurrentDictionary`, and the short-code counter is also in memory. This works on a single instance but not across several: each instance or replica has its own copy, so a link created on one may answer `404` on another. It is documented, shown live with `X-Instance-Id`, and the planned fix (Azure SQL Database) is described in [`docs/TUTORIAL.md`](./docs/TUTORIAL.md) under *Known weaknesses*.

---

## 🚀 Running locally

```bash
cd src/BeaconSalami
dotnet run
```

The app listens on `http://localhost:5001` by default (check the terminal output for the exact port).

Run the tests:

```bash
dotnet test
```

---

## ☁️ Deployment

- A push to `main` that changes the app builds, tests and deploys it with GitHub Actions. Each pipeline ends with a smoke test (`scripts/health-check.sh`) that confirms the app really answers before the run is marked successful. Changes to `*.md` files do not trigger a deployment.
- Both pipelines can also be started by hand: `gh workflow run deploy.yml` and `gh workflow run deploy-container.yml`.
- All infrastructure is described in `infra/*.bicep`. `scripts/provision-all.sh <resource-group>` creates both tracks from an empty resource group; the remaining steps (OIDC identity, pipeline variables, publish-profile secret) are listed in the *From zero to running* section of the tutorial.

## 📁 Repository layout

```
src/BeaconSalami/        the app and its Dockerfile
tests/BeaconSalami.Tests/ unit tests
infra/                   Bicep templates and parameter files
scripts/                 provisioning, deployment and health-check scripts
.github/workflows/       the two pipelines
docs/TUTORIAL.md         build log, rebuild guide, known weaknesses
```

See [`docs/TUTORIAL.md`](./docs/TUTORIAL.md) for the full reasoning behind every decision.
