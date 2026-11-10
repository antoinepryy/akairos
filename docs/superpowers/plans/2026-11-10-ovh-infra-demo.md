# OVH demo infra (bastion, vRack, LB, compute) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Terraform root module that builds, in the OVH Public Cloud project "D&A Engineering", a private network on the vRack, a bastion, N private nginx instances and an Octavia load balancer, then destroys it all cleanly.

**Architecture:** Single flat root module in `infra/`, provider `ovh/ovh` only (v2.24 covers private network, subnet v2, gateway, instance, loadbalancer with inline listeners/pools/members). Fixed private IPs computed with `cidrhost()` so LB members and SSH config are known at plan time. Bastion gets a public Ext-Net interface (`public = true`) plus the private one; compute instances are private only and reach the Internet through the gateway SNAT. cloud-init templates configure nginx (compute) and the SSH firewall (bastion).

**Tech Stack:** Terraform 1.16.6 (installed), provider `ovh/ovh ~> 2.24`, `terraform test` with `mock_provider`, cloud-init, nginx, bash + shellcheck.

**Spec:** `docs/superpowers/specs/2026-11-10-ovh-infra-demo-design.md`

## Global Constraints

- Project id `120a120c626c48d28773c56e42bce375` (variable `service_name`, this value as default); vRack `pn-1380461` already attached, **never** managed by Terraform.
- Every resource name starts with `akairos-` (variable `prefix`, default `"akairos"`).
- Region default `GRA11` (variable `region`).
- `instance_count` default `2`, validated `1..5`.
- Credentials only via env `OVH_ENDPOINT`, `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY`; no secret value in any committed file; state local and git-ignored.
- Compute instances: no public interface, no floating IP.
- Bastion SSH (22) allowed only from `admin_cidr`; key auth only.
- SSH public key default `~/.ssh/id_ed25519.pub` (variable `ssh_public_key_path`).
- Smallest flavors: instances `d2-2` (variable `flavor_name`), LB flavor `small`, gateway model `s`; `billing_period = "hourly"`.
- Do not create, modify or delete anything outside resources declared here (bucket `dna-backups-cronos` and S3 users must stay untouched).
- Code/comments in English, README in French.
- Commits: no AI attribution lines (blocked by hook); commit with `env -u GPG_TTY git commit`.

## Review Focus

1. `admin_cidr` given without a mask (e.g. `83.194.92.4`) → validation error, not a bastion open to nothing or to all. Test in Task 1.
2. `instance_count` lowered from 3 to 2 → LB member list shrinks with the instances (members derived from the same `range`), no dangling member. Test in Task 4.
3. Instance not yet serving (cloud-init still running) → LB health monitor on `/health` keeps it out of rotation. Asserted in Task 4.
4. Admin IP changes between sessions (home box re-IP) → `env.sh` recomputes `TF_VAR_admin_cidr`; README tells to re-run `apply`. Covered in Task 5.
5. `terraform destroy` leaves a floating IP or gateway behind → `check-leftovers.sh` lists any `akairos-*` instance, network, gateway, LB or floating IP left in the region and exits non-zero. Task 5, run in Task 6.

---

### Task 1: Skeleton, variables, credentials wrapper

**Files:**
- Create: `infra/versions.tf`, `infra/variables.tf`, `infra/locals.tf`, `env.sh`, `infra/tests/variables.tftest.hcl`

**Interfaces:**
- Produces variables: `service_name` (string), `region` (string), `prefix` (string), `instance_count` (number), `flavor_name` (string), `admin_cidr` (string, required, CIDR-validated), `ssh_public_key_path` (string), `subnet_cidr` (string, default `"10.42.0.0/24"`), `vlan_id` (number, default `42`).
- Produces locals: `local.bastion_ip = cidrhost(var.subnet_cidr, 5)`, `local.app_ips = [for i in range(var.instance_count) : cidrhost(var.subnet_cidr, 10 + i)]`, `local.app_names = [for i in range(var.instance_count) : "${var.prefix}-app-${i + 1}"]`.
- `env.sh` (sourced, not executed): loads `~/.config/infra/secrets.env`, exports `OVH_ENDPOINT=ovh-eu`, `OVH_APPLICATION_KEY=$OVH_FULL_APP_KEY`, `OVH_APPLICATION_SECRET=$OVH_FULL_APP_SECRET`, `OVH_CONSUMER_KEY=$OVH_FULL_CONSUMER_KEY`, and `TF_VAR_admin_cidr="$(curl -fsS https://api.ipify.org)/32"`. Contains no value itself.

- [ ] **Step 1: Write failing tests** in `infra/tests/variables.tftest.hcl` with `mock_provider "ovh" {}`, `command = plan`, `variables { admin_cidr = "1.2.3.4/32" ... }`:
  - `run "defaults"`: assert `length(local.app_ips) == 2`, `local.app_ips[0] == "10.42.0.10"`, `local.bastion_ip == "10.42.0.5"`, `local.app_names[1] == "akairos-app-2"`.
  - `run "admin_cidr_without_mask"`: `admin_cidr = "1.2.3.4"`, `expect_failures = [var.admin_cidr]`.
  - `run "too_many_instances"`: `instance_count = 6`, `expect_failures = [var.instance_count]`.
- [ ] **Step 2:** `cd infra && terraform init -backend=false && terraform test` → FAIL (variables undefined).
- [ ] **Step 3:** Write `versions.tf` (`required_version = ">= 1.9"`, `ovh/ovh ~> 2.24`, empty `provider "ovh" {}`), `variables.tf` (validation: `can(cidrnetmask(var.admin_cidr))`; `instance_count >= 1 && <= 5`), `locals.tf`, `env.sh`. Add `infra/.terraform.lock.hcl` to git (keep), state ignored by root `.gitignore`.
- [ ] **Step 4:** `terraform fmt -check -recursive && terraform validate && terraform test` → all pass; `shellcheck env.sh` → clean.
- [ ] **Step 5:** Commit `feat: terraform skeleton, variables and credentials wrapper`.

### Task 2: Private network, subnet, gateway

**Files:**
- Create: `infra/network.tf`, `infra/tests/network.tftest.hcl`

**Interfaces:**
- Consumes: Task 1 variables/locals.
- Produces: `ovh_cloud_project_network_private.this` (`name = "${var.prefix}-net"`, `vlan_id = var.vlan_id`, `regions = [var.region]`), `ovh_cloud_project_network_private_subnet_v2.this` (`name = "${var.prefix}-subnet"`, `cidr = var.subnet_cidr`, `dhcp = true`, `allocation_pools` `.100`–`.200` so fixed IPs `.5`–`.15` never collide with DHCP), `ovh_cloud_project_gateway.this` (`name = "${var.prefix}-gw"`, `model = "s"`). Network id for regional resources: use the `regions_attributes`/`openstackid` exposed by the network resource for `var.region` (check provider doc; `ovh_cloud_project_region_network` is the alternative if needed — pick one and note it in a comment).

- [ ] **Step 1: Write failing test** `run "network"` (plan, mock provider): assert names `akairos-net`, `akairos-subnet`, `akairos-gw`, `vlan_id == 42`, subnet `cidr == "10.42.0.0/24"`, gateway `model == "s"`.
- [ ] **Step 2:** `terraform test` → FAIL.
- [ ] **Step 3:** Implement `network.tf`.
- [ ] **Step 4:** `terraform validate && terraform test` → pass.
- [ ] **Step 5:** Commit `feat: private network, subnet and gateway on vRack`.

### Task 3: SSH key, bastion, app instances, cloud-init

**Files:**
- Create: `infra/instances.tf`, `infra/data.tf`, `infra/templates/app.yaml.tftpl`, `infra/templates/bastion.yaml.tftpl`, `infra/tests/instances.tftest.hcl`

**Interfaces:**
- Consumes: Task 2 network/subnet/gateway ids, Task 1 locals.
- Produces: `ovh_cloud_project_ssh_key.this` (`name = "${var.prefix}-key"`), `ovh_cloud_project_instance.bastion`, `ovh_cloud_project_instance.app` (`count = var.instance_count`), data sources `ovh_cloud_project_flavors` (filter `var.flavor_name`) and `ovh_cloud_project_images` (Linux, pick the newest image whose name starts with `"Debian 12"`).
- `app.yaml.tftpl(name)`: installs nginx; writes `/var/www/html/index.html` at boot with hostname, private IP (`hostname -I`), boot time, and a distinct background color derived from the hostname; `/health` returns `200 ok` (nginx `location = /health`).
- `bastion.yaml.tftpl(admin_cidr)`: `ssh_pwauth: false`, installs `ufw`, `default deny incoming`, allow `22/tcp from ${admin_cidr}` on the public interface, allow `22/tcp` from `var.subnet_cidr`, enable; `unattended-upgrades`.
- Bastion: `network { public = true; private { network {id, subnet_id}; ip = local.bastion_ip; gateway { id } } }`. App: same `private` block with `ip = local.app_ips[count.index]`, **no** `public`, no floating IP.

- [ ] **Step 1: Write failing tests** (plan, mock provider with `mock_data "ovh_cloud_project_flavors"` / `mock_data "ovh_cloud_project_images"` defaults):
  - `run "app_instances"`: `instance_count = 3` → `length(ovh_cloud_project_instance.app) == 3`, names `akairos-app-1..3`, every app `network` has `public` null or false, `billing_period == "hourly"`, `strcontains(app[0].user_data, "location = /health")`.
  - `run "bastion"`: `admin_cidr = "1.2.3.4/32"` → bastion `public == true`, `strcontains(bastion.user_data, "1.2.3.4/32")`, `strcontains(bastion.user_data, "ssh_pwauth: false")`.
- [ ] **Step 2:** `terraform test` → FAIL.
- [ ] **Step 3:** Implement files.
- [ ] **Step 4:** `terraform validate && terraform test` → pass.
- [ ] **Step 5:** Commit `feat: bastion and app instances with cloud-init`.

### Task 4: Load balancer and outputs

**Files:**
- Create: `infra/loadbalancer.tf`, `infra/outputs.tf`, `infra/tests/loadbalancer.tftest.hcl`

**Interfaces:**
- Consumes: Task 1 locals, Task 2 network/subnet/gateway, Task 3 `ovh_cloud_project_instance.app` (dependency only; members use `local.app_ips`).
- Produces: `ovh_cloud_project_loadbalancer.this` (`name = "${var.prefix}-lb"`, flavor id from `data.ovh_cloud_project_loadbalancer_flavors` where name `small`, `network.private` with `floating_ip_create`, gateway id), one listener `HTTP:80`, pool `ROUND_ROBIN` HTTP, health monitor `HTTP GET /health` expected `200`, delay 5, timeout 3, max_retries 2; members `[for i, ip in local.app_ips : { name = local.app_names[i], address = ip, protocol_port = 80 }]`.
- Outputs: `lb_url` (`"http://${floating ip}"`), `bastion_ip` (the bastion address not inside `var.subnet_cidr`), `app_private_ips` (`local.app_ips`), `ssh_config` (heredoc: `Host akairos-bastion` + one `Host akairos-app-N` per instance with `ProxyJump akairos-bastion`, `User debian`).

- [ ] **Step 1: Write failing tests** (plan, mock provider):
  - `run "members_follow_count"`: `instance_count = 3` → `length(...listeners[0].pool.members) == 3`; second run `instance_count = 2` → `== 2`, `members[1].address == "10.42.0.11"`.
  - `run "health_monitor"`: `url_path == "/health"`, `expected_codes == "200"`, listener `port == 80`.
  - `run "ssh_config"`: `strcontains(output.ssh_config, "ProxyJump akairos-bastion")`, contains `Host akairos-app-2`.
- [ ] **Step 2:** `terraform test` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `terraform fmt -check -recursive && terraform validate && terraform test` → pass.
- [ ] **Step 5:** Commit `feat: octavia load balancer and outputs`.

### Task 5: Demo scripts and README

**Files:**
- Create: `scripts/verify.sh`, `scripts/check-leftovers.sh`, `README.md`

**Interfaces:**
- Consumes: Task 4 outputs (`terraform -chdir=infra output -raw lb_url`).
- `verify.sh [n=20]`: curls `lb_url` n times, extracts the hostname, prints counts per hostname; exits 1 if fewer than 2 distinct names when `instance_count >= 2`.
- `check-leftovers.sh`: signed `GET` calls on `/cloud/project/{P}/instance`, `/network/private`, `/region/{R}/gateway`, `/region/{R}/loadbalancing/loadbalancer`, `/region/{R}/floatingip`; prints any item whose name starts with `akairos-` (floating IPs: any not attached to a non-akairos resource); exit 1 if any; also confirms bucket `dna-backups-cronos` still listed under `/region/EU-WEST-PAR/storage`. Uses the env vars from `env.sh`; no secret printed.
- README (French): prerequisites (Terraform, OVH API key with how a trainee creates one on https://eu.api.ovh.com/createToken/ — rights `GET/POST/PUT/DELETE /cloud/project/{id}/*`), `source env.sh`, `apply`, demo script (répartition via `verify.sh`, SSH via bastion with `ssh_config` output, direct SSH to an app IP impossible, `-var instance_count=3`, stop nginx on one instance → leaves the pool within ~15 s, restart → comes back), `destroy` + `check-leftovers.sh`, note: re-run `apply` if home IP changed; rough hourly cost.

- [ ] **Step 1:** `shellcheck scripts/*.sh env.sh` → clean.
- [ ] **Step 2:** `bash -n` on each script; `check-leftovers.sh` run now (nothing created yet) → exit 0 and bucket found.
- [ ] **Step 3:** Commit `feat: demo verification scripts and README`.

### Task 6: Live run (costs money: confirm with Antoine first)

- [ ] **Step 1:** `source env.sh && terraform -chdir=infra init && terraform -chdir=infra plan` → only `akairos-*` resources, ~ `2 + instance_count + 4` to add, 0 change/destroy.
- [ ] **Step 2:** `apply` → success; `scripts/verify.sh` → ≥ 2 distinct hostnames.
- [ ] **Step 3:** SSH to `akairos-app-1` via ProxyJump → works; `curl -m 5` / `ssh` to the app private IP without bastion → fails (no route).
- [ ] **Step 4:** `apply -var instance_count=3` → `verify.sh` shows 3 names. Stop nginx on app-1 → disappears from responses within 20 s; start → returns.
- [ ] **Step 5:** `destroy` → success; `scripts/check-leftovers.sh` → exit 0, bucket intact.
- [ ] **Step 6:** Fix anything found (provider quirks, image name), re-run steps 1–5, commit `fix: ...` with what changed and update README.
