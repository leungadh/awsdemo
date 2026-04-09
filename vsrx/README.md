# vSRX Configuration Guide

## Step 1 — Wait for vSRX to boot

After `terraform apply`, the vSRX takes **3–5 minutes** to boot. Check readiness:

```bash
ssh -i ~/.ssh/<your-key>.pem root@<vsrx-mgmt-eip> "show version"
```

Retry every 30 seconds until it responds. The management IP is in `terraform output vsrx_mgmt_public_ip`.

---

## Step 2 — Download IDP signatures (do this FIRST, takes ~15–20 min)

SSH in and start the download before doing anything else:

```
ssh -i ~/.ssh/<your-key>.pem root@<vsrx-mgmt-eip>
cli
request security idp security-package download
```

Check progress every few minutes:

```
request security idp security-package download status
```

Once download completes, install:

```
request security idp security-package install
show security idp security-package-version
```

Wait until you see `"Update successful"` before proceeding.

---

## Step 3 — Apply baseline configuration

Still in the vSRX CLI session:

```
configure
```

Now paste the entire contents of `vsrx/baseline.conf` (everything after the header comments).

Then commit:

```
commit and-quit
```

---

## Step 4 — Verify

```
show interfaces terse
show security zones
show security policies
show security idp status
show security screen ids-option untrust-screen
```

Expected:
- `ge-0/0/0.0` up with 10.0.1.254/24
- `ge-0/0/1.0` up with 10.0.2.254/24
- Zones `untrust` and `trust` configured
- IDP status: active with current signatures

---

## Connectivity test before demo

From Kali (`ssh kali@<kali-eip>`):

```bash
# Should reach web server through vSRX
ping -c 3 10.0.2.100
curl -s http://10.0.2.100/
```

From vSRX:

```
show security flow session
```

Should show active sessions for the ping/curl traffic.

---

## Resetting between scenarios

To clear screen counters and session table between demo runs:

```
clear security screen statistics
clear security flow session all
```

To reset IDP counters:

```
clear security idp counters
```
