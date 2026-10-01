## What and why

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] `terraform fmt` and `terraform validate` pass
- [ ] `terraform plan` is clean after the change (no perpetual drift)
- [ ] Shell and Python files parse (`bash -n`, `python3 -m py_compile`)
- [ ] No OCIDs, public IPs, profile names, account names or secrets in the diff
- [ ] Docs updated (`deploy/README.md`, `docs/ARCHITECTURE.md`, `docs/PILOT.md`) where behaviour changed
