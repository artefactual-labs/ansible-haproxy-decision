# ansible-haproxy-decision

Ansible role that installs and configures HAProxy 2.8 together with optional SPOA
helpers (decision-spoa, coraza-spoa, cookie-guard-spoa). The role favours the
Artefactual packaging pipeline for Enterprise Linux builds and the `ppa:vbernat/haproxy-2.8`
PPA on Ubuntu.

## Highlights

- Downloads GitHub release artifacts for HAProxy 2.8 on Red Hat Enterprise Linux
  derivatives from [`haproxy-el-packaging`](https://github.com/artefactual-labs/haproxy-el-packaging).
- Installs HAProxy and renders a configurable `haproxy.cfg` that can automatically
  include SPOE snippets managed by the role.
- Optionally installs and configures `decision-spoa`, `coraza-spoa`, and
  `cookie-guard-spoa`, wiring each daemon into HAProxy through dedicated templates.
- Exposes variables to customise repository locations, package names, backend
  endpoints, and service runtime arguments without having to fork the role.

## Requirements

- Ansible 2.13+
- Supported operating systems:
  - Rocky/Alma/RHEL 8 or 9 (or compatible)
  - Ubuntu 20.04 (Focal) or 22.04 (Jammy)

> **Note:** This role does not manage firewall rules or SELinux policy. Adapt
> those separately if your platform requires them.

## Repository configuration

Enterprise Linux hosts are expected to consume RPMs published through
`haproxy-el-packaging`. Provide the repository endpoint and matching GPG key:

```yaml
haproxy_decision_rhel_repo:
  name: artefactual-haproxy
  description: Artefactual HAProxy 2.8 packages
  baseurl: https://packages.example.org/rocky/$releasever/$basearch
  gpgkey: https://packages.example.org/keys/RPM-GPG-KEY-artefactual
```

Ubuntu hosts keep using `ppa:vbernat/haproxy-2.8` by default. Additional APT
repositories (for the SPOA packages, for example) can be supplied via
`haproxy_decision_apt_repos`.

Set `haproxy_decision_manage_repo` to `false` if the target host already has the
required repositories configured.

## Key variables

| Variable | Default | Description |
| --- | --- | --- |
| `haproxy_decision_manage_repo` | `true` | Toggle repository management. |
| `haproxy_decision_haproxy_repo` | `artefactual-labs/haproxy-el-packaging` | GitHub repository hosting the HAProxy RPM release assets. |
| `haproxy_decision_haproxy_version` | `2.8.16` | Release tag used to compose download URLs for HAProxy RPMs. |
| `haproxy_decision_haproxy_release_number` | `1` | Packaging release identifier appended to the RPM name (e.g. `-1.el9`). |
| `haproxy_decision_haproxy_rpm_arch` | `x86_64` | Architecture suffix used when deriving the default RPM filename. |
| `haproxy_decision_haproxy_rpm` | `""` | Optional override for the full HAProxy RPM filename. Leave empty to derive `haproxy-<version>-<release>.el<major>.<arch>.rpm` automatically. |
| `haproxy_decision_haproxy_checksums` | `{}` | Optional checksum map keyed by EL major version (e.g. `"9": "sha256:..."`). |
| `haproxy_decision_spoa_releases` | see defaults | Mapping keyed by SPOA name (`decision`, `coraza`, `cookie_guard`) that exposes per-OS package URLs (`rh_package_url`, `debian_package_url`, or `package_urls.*`) plus optional checksum settings (`use_checksum`, `checksums_url`, `checksums`). Override entries to point at your own builds. |
| `haproxy_decision_haproxy_package` | `haproxy` | (Debian/Ubuntu) Package name used with `apt`. Override if you need a specific NEVRA. |
| `haproxy_decision_manage_config` | `true` | When `true` the role renders `haproxy.cfg` from `templates/haproxy.cfg.j2`. |
| `haproxy_decision_manage_certificates` | `false` | When `true` the role assembles HAProxy-ready PEM bundles under `haproxy_decision_certificate_dir`. |
| `haproxy_decision_certificates` | `[]` | List of TLS certificate definitions pulling from Certbot or other sources; each entry can point at `fullchain` and `privkey` paths or a pre-built bundle. |
| `haproxy_decision_certificate_bootstrap_enabled` | `true` | Controls whether the role generates a short-lived self-signed bundle when referenced certificate files are missing so HAProxy can start. |
| `haproxy_decision_manage_certbot_hook` | `false` | Deploy a Certbot deploy-hook script that rebuilds managed PEM bundles and reloads HAProxy immediately after renewal. |
| `haproxy_decision_certbot_hook_path` | `/etc/letsencrypt/renewal-hooks/deploy/haproxy-decision-certificates.sh` | Destination of the managed deploy-hook script. |
| `haproxy_decision_certbot_hook_owner` / `_group` / `_mode` | see defaults | Ownership and permissions applied to the deploy-hook script. |
| `haproxy_decision_certbot_hook_reload_command` | `systemctl reload haproxy` | Command executed by the hook after regenerating PEM bundles. |
| `haproxy_decision_global_settings` / `haproxy_decision_defaults_settings` | see defaults | Lists of directives written to the `global` and `defaults` sections. |
| `haproxy_decision_listeners`, `haproxy_decision_frontends`, `haproxy_decision_backends` | `[]` | Optional lists of sections appended to the generated configuration. |
| `haproxy_decision_manage_decision_policy` | `false` | When `true` and the `decision` SPOA is enabled, the role creates `/etc/decision-policy` (override with `haproxy_decision_decision_policy_dir`) and renders a managed `policy.yml`. |
| `haproxy_decision_decision_policy` | `{}` | Mapping rendered into the policy file via `to_nice_yaml`. Mirror the structure described in the decision-spoa documentation. |
| `haproxy_decision_manage_decision_context` | `false` | Controls whether the optional `context.yml` is rendered (co-located with `policy.yml`). Set alongside `haproxy_decision_decision_context`. |
| `haproxy_decision_decision_context` | `{}` | Dictionary rendered to `context.yml` to drive Decision’s trusted-session tagging. Mirrors the structure described in the upstream README. |
| `haproxy_decision_manage_decision_secret` | `false` | Creates `{{ haproxy_decision_decision_secret_dir }}` and manages the HMAC secret referenced by `context.yml` (default `secrets/edge_hmac.key`). Provide either `_secret_src` (role file) or `_secret_content`. |
| `haproxy_decision_decision_secret_generate` | `true` | When no `_secret_src`/`_secret_content` is supplied, generate a random base64 secret (length controlled by `_secret_generate_bytes`) the first time the role runs. |
| `haproxy_decision_decision_configcheck_enabled` | `true` | Runs `decision-configcheck` (default `/usr/local/bin/decision-configcheck -root {{ haproxy_decision_decision_policy_dir }}`) after updating policy/context files to catch syntax errors early. Override `_configcheck_bin`/`_configcheck_args` to customize the command or disable by setting this to `false`. |
| `haproxy_decision_spoas` | see defaults | Dictionary describing each SPOA daemon. Set `enabled: true` to activate one, adjust service/backend data, and rely on `haproxy_decision_spoa_releases` for download metadata when installing from GitHub releases. |
| `haproxy_decision_manage_spoa_configs` | `true` | Controls whether the role writes SPOE configuration snippets. |
| `haproxy_decision_manage_spoa_env` | `true` | Controls whether `/etc/default/*` files are managed for SPOAs. |
| `haproxy_decision_manage_spoa_services` | `true` | Enable or disable service/timer management for SPOAs. |
| `haproxy_decision_cookie_guard_altcha_page_template` | `""` | Optional template rendered to `/altcha` (set to a role path such as `files/altcha_challenge.html.lf.j2` when you need to override the package-provided file). Leave blank to keep the file managed by the cookie-guard-spoa package. |
| `haproxy_decision_cookie_guard_altcha_page_dest` | `{{ haproxy_decision_config_dir }}/altcha_challenge.html.lf` | Location of the challenge page when you opt-in to managing it via the role. |
| `haproxy_decision_cookie_guard_manage_altcha_assets` | `false` | When true, the role stages `altcha.min.js` under `{{ haproxy_decision_cookie_guard_altcha_assets_dir }}/<version>/`, writes a `VERSION` file, and refreshes the `active` symlink. Leave `false` to rely on the cookie-guard-spoa package installing/updating the assets. |
| `haproxy_decision_cookie_guard_altcha_page_owner` / `_group` / `_mode` | see defaults | Ownership and permissions applied to the managed ALTCHA HTML page. |
| `haproxy_decision_cookie_guard_altcha_assets_dir` / `_version` / `_asset_src` | see defaults | Controls where ALTCHA JS assets are installed and the label/source to copy when `manage_altcha_assets` is enabled. Keep `_asset_src` empty when relying on packages. |
| `haproxy_decision_cookie_guard_altcha_assets_owner` / `_group` / `_mode` | see defaults | Ownership and permissions enforced on the ALTCHA asset tree plus `VERSION`. |
| `haproxy_decision_coraza_spoa_relax_systemd` | `false` | When `true` the role installs a systemd drop-in that removes the `BindReadOnlyPaths=-/etc/ld.so.cache` restriction from the `coraza-spoa` service. |
| `haproxy_decision_release_url_template` | `https://github.com/{repo}/releases/download/{version}/{asset}` | Base template used to compose download URLs for GitHub releases. |
| `haproxy_decision_haproxy_url_template` | `haproxy_decision_release_url_template` | Template applied to HAProxy downloads. Package entries may override it per release. |
| `haproxy_decision_rhel_disable_gpg_check` | `false` | Disable RPM signature verification for HAProxy and SPOA downloads (useful in CI if upstream artifacts are unsigned). |
| `haproxy_decision_spoa_release_url_template` | same as above | Base template used for SPOA downloads. Individual entries may override it with `haproxy_decision_spoas.<name>.release.url_template`. |

Refer to `defaults/main.yml` for the full catalogue of variables.

## Example playbook

```yaml
- name: Deploy HAProxy with decision and coraza SPOAs
  hosts: loadbalancers
  become: true
  vars:
    haproxy_decision_rhel_repo:
      name: artefactual-haproxy
      description: Artefactual HAProxy 2.8
      baseurl: https://releases.example.com/haproxy/el$releasever/$basearch
      gpgkey: https://releases.example.com/haproxy/RPM-GPG-KEY-artefactual
    haproxy_decision_spoas:
      decision:
        enabled: true
        backend:
          servers:
            - name: decision
              address: 127.0.0.1
              port: 9908
              options: check inter 5s
      coraza:
        enabled: true
      cookie_guard:
        enabled: false
    haproxy_decision_frontends:
      - name: www
        lines:
          - "bind *:80"
          - "mode http"
          - "default_backend app_servers"
        templates:
          - src: snippets/frontend-path-acl.cfg.j2
            vars:
              acl_name: is_api
              path_prefix: /api
              backend: varnish_backend
    haproxy_decision_backends:
      - name: app_servers
        lines:
          - "mode http"
          - "balance roundrobin"
          - "server app1 10.0.0.10:8080 check"
  roles:
    - ansible-haproxy-decision
```

Each `listener`, `frontend`, and `backend` entry can optionally supply a single
`template` (with `template_vars`) or a `templates` list. These snippets are
rendered with Ansible’s template lookup and appended after the static `lines`,
which lets you reuse complex fragments while keeping simple cases inline.

## Cookie-guard ALTCHA flow

Enabling `haproxy_decision_spoas.cookie_guard.enabled` now deploys everything
required to run the built-in ALTCHA challenge provided by
[`cookie-guard-spoa`](https://github.com/artefactual-labs/cookie-guard-spoa):

- The cookie-guard-spoa package already installs `/etc/haproxy/altcha_challenge.html.lf`
  plus the ALTCHA assets under `/etc/haproxy/assets/altcha/`. The role leaves
  these files untouched by default. Provide
  `haproxy_decision_cookie_guard_altcha_page_template` or set
  `haproxy_decision_cookie_guard_manage_altcha_assets: true` only when you need
  to override them (for example, to ship a custom HTML page or bundle a specific
  JS release under version control).
- Default CLI flags include `-cookie-secure`, `-altcha-assets`, and
  `-altcha-page` so the agent knows where to find these files.
- The managed SPOE template now emits both the TCP backend that HAProxy uses for
  SPOE frames and an HTTP backend (`cookie_guard_http_backend` by default) that
  points to the agent’s metrics port.

Expose the endpoints by adding a simple ACL to any frontend that should serve
ALTCHA traffic:

```
acl altcha_routes path_beg -i /altcha /altcha- /assets/altcha/
use_backend cookie_guard_http_backend if altcha_routes
```

When HAProxy decides a client needs a challenge (for example, when
`var(txn.cookieguard.valid) -m str 1` fails), redirect them to `/altcha` and
preserve the original path so the page can return once the hb_v2 cookie is set:

```
http-request redirect code 302 location /altcha?url=%[req.uri] if chal_target !cookie_ok
```

You can override any of the `_altcha_*` variables to bring your own HTML, take
over asset management, or point the generated HTTP backend at a different
listener. Adjust `haproxy_decision_spoas.cookie_guard.http_backend` if you
prefer a different backend name or need to disable the section entirely. Keep
`haproxy_decision_cookie_guard_manage_altcha_assets: false` (default) when the
cookie-guard-spoa package provides `/etc/haproxy/assets/altcha` for you.

## Decision context + secrets

When running `decision-spoa` you often need to ship a policy bundle that now
consists of:

```
/etc/decision-policy /
  policy.yml          # request rules
  context.yml         # response allowlist and trusted-session tags
  secrets/
    edge_hmac.key     # HMAC secret referenced by context.yml
```

Enable `haproxy_decision_manage_decision_policy` to create the base directory
and render `policy.yml`. To manage the other files:

- `haproxy_decision_manage_decision_context: true` renders
  `{{ haproxy_decision_decision_context_path }}` from the
  `haproxy_decision_decision_context` mapping via
  `templates/spoa/context.yml.j2`. Match the schema in the upstream
  [Trusted context](https://github.com/artefactual-labs/decision-spoa#trusted-context-contextyml)
  section (response allowlist + tags, hashing mode, secret path).
- `haproxy_decision_manage_decision_secret: true` ensures
  `{{ haproxy_decision_decision_secret_dir }}` exists and writes the secret to
  `{{ haproxy_decision_decision_secret_path }}`. Provide either
  `haproxy_decision_decision_secret_src` (path relative to this role’s `files/`
  directory or the Ansible control machine) or
  `haproxy_decision_decision_secret_content` (inline string). Leave both empty to
  let the role generate a base64 secret once (length controlled by
  `haproxy_decision_decision_secret_generate_bytes`). The task runs with `no_log`
  enabled by default.
- Set `haproxy_decision_decision_configcheck_enabled: true` (default) to invoke
  `decision-configcheck` after rendering the files. This mirrors running
  `decision-configcheck -root /etc/decision-policy` manually and fails fast when
  either YAML file is invalid.

All three tasks notify the `decision-spoa` service so changes take effect
immediately (or at the next handler run, depending on your play). When the
secret path is relative (default `secrets/edge_hmac.key`) the role keeps it under
`haproxy_decision_decision_policy_dir`, mirroring the layout described in the
Decision README.

## Certificate management

Enable `haproxy_decision_manage_certificates` to have the role assemble the `.pem`
bundles that HAProxy expects under `haproxy_decision_certificate_dir`. Certificates
can come from Certbot or any other CA—point each entry at either a combined PEM or
the separate `fullchain` and `privkey` files exposed on the target host:

```yaml
haproxy_decision_manage_certificates: true
haproxy_decision_certificates:
  - name: apps
    domains:
      - apps.example.org
    fullchain_path: /etc/letsencrypt/live/apps.example.org/fullchain.pem
    privkey_path: /etc/letsencrypt/live/apps.example.org/privkey.pem
```

When the referenced files are missing (for example, before Certbot provisions a
fresh certificate), the role drops a short-lived self-signed bundle so HAProxy can
start and continue proxying ACME HTTP-01 traffic. Tune this bootstrap behaviour
with `haproxy_decision_certificate_bootstrap_enabled`, `*_valid_days`, and the
other `haproxy_decision_certificate_bootstrap_*` variables.

Set `haproxy_decision_manage_certbot_hook: true` to have the role install a
Certbot deploy hook that rebuilds any managed PEM bundles sourced from
`/etc/letsencrypt/live/<domain>/` and then executes
`haproxy_decision_certbot_hook_reload_command` (defaults to reloading the
HAProxy service). This keeps certificates fresh immediately after every renewal
without waiting for the next configuration run.

### Using the role with Certbot

The [geerlingguy.certbot](https://github.com/geerlingguy/ansible-role-certbot)
role stores issued material under `/etc/letsencrypt/live/<domain>/` and lets you
describe each request via `certbot_certs`. To keep HAProxy running while
performing HTTP-01 challenges, configure a dedicated backend that proxies ACME
requests to Certbot’s standalone listener on `127.0.0.1:8009`:

```yaml
- hosts: loadbalancers
  become: true
  vars:
    haproxy_decision_manage_certificates: true
    haproxy_decision_certificates:
      - name: apps
        domains: ["apps.example.org"]
        fullchain_path: /etc/letsencrypt/live/apps.example.org/fullchain.pem
        privkey_path: /etc/letsencrypt/live/apps.example.org/privkey.pem
    haproxy_decision_frontends:
      - name: public_http
        lines:
          - "bind *:80"
          - "mode http"
          - "acl is_certbot path_beg -i /.well-known/acme-challenge"
          - "use_backend certbot if is_certbot"
          - "http-request redirect scheme https unless { ssl_fc } || is_certbot"
          - "default_backend app_servers"
    haproxy_decision_backends:
      - name: certbot
        lines:
          - "mode http"
          - "server certbot_local 127.0.0.1:8009"
      - name: app_servers
        lines:
          - "mode http"
          - "server app1 10.0.0.10:8080 check"
    certbot_certs:
      - domains: ["apps.example.org"]
    certbot_create_method: standalone
    certbot_create_standalone_stop_services: []
    certbot_create_command: >-
      {{ certbot_script }} certonly --{{ certbot_create_method }}
      {{ '--test-cert' if certbot_testmode else '' }}
      --noninteractive --agree-tos
      --email {{ cert_item.email | default(certbot_admin_email) }}
      --http-01-port 8009
      -d {{ cert_item.domains | join(',') }}
  roles:
    - role: artefactual.ansible-haproxy-decision
    - role: geerlingguy.certbot
  tasks:
    - name: Refresh HAProxy certificate bundles after Certbot runs
      ansible.builtin.import_role:
        name: artefactual.ansible-haproxy-decision
        tasks_from: certificates.yml
```

The first role run installs HAProxy and, if necessary, seeds it with a bootstrap
certificate. Certbot (proxied through HAProxy on `/.well-known/acme-challenge`)
then retrieves trusted material, and the final task rebuilds the HAProxy bundles
from Certbot’s live files—which triggers a graceful reload through the built-in
handler whenever the certificate changes. On future renewals you can rerun just
the certificate logic with `ansible-playbook … --tags haproxy-decision-certificates`
or invoke it from a Certbot deploy hook so HAProxy picks up the new bundle
immediately.

## SPOA customisation

Each SPOA definition accepts overrides that feed directly into the templates:

- Set `service` for every enabled SPOA so the role can restart the unit after
  config or policy changes. The defaults ship with the appropriate values
  (`decision-spoa`, `coraza-spoa`, `cookie-guard-spoa`); keep them in your
  overrides unless you rename the systemd units.

- Adjust listener endpoints by modifying `backend.servers`.
- Override runtime arguments through `env_opts`.
- Inject extra HAProxy directives with `spoa.backend.extra_lines` or
  `spoa.extra_config`.
- Provide direct package URLs via `haproxy_decision_spoa_releases.<name>` when
  you need to source binaries from somewhere other than the defaults.
- Supply additional messages or groups for the Cookie Guard SPOA using the
  `messages` or `group_definitions` structures.
- Manage the Decision policy tree by setting `haproxy_decision_manage_decision_policy: true`
  and filling `haproxy_decision_decision_policy` with a mapping that matches
  the YAML schema documented upstream.

Example release override:

```yaml
haproxy_decision_spoa_releases:
  decision:
    rh_package_url: https://downloads.example.com/decision-spoa-1.2.3-2.el9.x86_64.rpm
    debian_package_url: https://downloads.example.com/decision-spoa_1.2.3_amd64.deb
    use_checksum: true
    checksums_url: https://downloads.example.com/decision-spoa-1.2.3.sha256
```

Legacy overrides that supply `haproxy_decision_spoas.<name>.release.assets`
still work, but migrating to the central `haproxy_decision_spoa_releases`
structure keeps package metadata in a single place. Consult the upstream
[`decision-spoa` README](https://github.com/artefactual-labs/decision-spoa#policy-configuration)
for the canonical policy layout and examples; mirror that structure when
populating `haproxy_decision_decision_policy`.
If a more drastic change is required, point `config_template` or `env_template`
to a custom template shipped alongside your playbook.

## Development

This role purposely avoids Molecule scaffolding for now. Run integration tests
with your preferred harness before promoting changes.

### Local end-to-end harness

The helper script `tests/e2e/run_e2e.sh` spins up a Rocky Linux 9 cloud image in
QEMU, applies `tests/e2e/site.yml`, runs the k6 smoke test, and gathers
Prometheus metrics. It keeps the VM around on failure so you can SSH in for
forensics. The script requires:

- `qemu-system-x86`
- `qemu-utils`
- `cloud-image-utils` (for `cloud-localds`)
- `sshpass`
- `netcat-openbsd`
- `python3-venv`
- `ansible-core` + `ansible`
- `k6` (downloaded automatically inside the guest if missing)

Example session:

```bash
sudo apt-get install qemu-system-x86 qemu-utils cloud-image-utils sshpass netcat-openbsd python3-venv
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install ansible-core==2.15.9 ansible==8.7.0
tests/e2e/run_e2e.sh
```

Set `vm_no_shutdown=1` (or `VM_NO_SHUTDOWN=1`) to keep the VM alive after the
smoke test finishes so you can inspect services manually:

```bash
vm_no_shutdown=1 tests/e2e/run_e2e.sh
```

The VM exposes SSH on `127.0.0.1:2222` using the `ansible` user/password. You
can connect with:

```bash
sshpass -p ansible ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@127.0.0.1
```

When you are done, clean up with `tests/e2e/stop_vm.sh`.

### GitHub Actions workflow

The CI workflow (`.github/workflows/e2e-rocky9.yml`) keeps using the very same
`tests/e2e/site.yml`, but orchestrates the steps directly: it calls
`tests/e2e/start_vm.sh` to boot the Rocky 9 guest locally, runs `ansible-playbook`
against the guest using the checked-in inventory, executes the shared
`tests/e2e/run_smoke.sh` helper to launch k6 and collect metrics, and finally
shuts the VM down with `tests/e2e/stop_vm.sh`. In CI we skip the nested VM and
instead launch a privileged Rocky Linux 9 container (with systemd) on the
standard `ubuntu-latest` runner, apply `tests/e2e/site.yml` inside that
environment via `tests/e2e/inventory-localhost.ini`, and execute the same smoke
test. Running the individual building blocks directly in CI improves log
visibility and keeps the workflow decoupled from the local convenience script,
while still validating the exact same playbook.
