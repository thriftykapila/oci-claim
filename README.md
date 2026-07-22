# OCI A1 Auto-Claim

Automatically claims an Oracle Cloud **Always Free** Ampere A1 instance (4 OCPU / 24 GB RAM) using GitHub Actions — no server or Mac required.

Runs every **5 minutes** via GitHub's free infrastructure and sends a **push notification** the moment capacity is available.

## How it works

1. GitHub Actions cron triggers every 5 minutes (free on public repos)
2. Attempts to launch `VM.Standard.A1.Flex` across **all availability domains** in your region
3. If Oracle returns "Out of host capacity" → waits and retries next cron run
4. When claimed → sends push notification via [ntfy.sh](https://ntfy.sh) and exits

---

## Full Setup Guide

### Step 1 — Upgrade Oracle account to Pay As You Go

> The Always Free A1 quota (4 OCPU / 24 GB) is only available after upgrading.  
> You will **not be charged** — A1 is permanently free. The upgrade just unlocks the quota.

1. Log in at **https://cloud.oracle.com**
2. Click your **avatar (top-right)** → **Upgrade to Paid**
3. Enter a credit card for identity verification
4. **Recommended**: Set a budget alert at $1 so you're notified of any accidental charges:
   - OCI Console → **Billing & Cost Management** → **Budgets** → **Create Budget** → Amount: `$1` → add your email

---

### Step 2 — Generate OCI API Keys (on your Mac)

Run these commands in your terminal. These create the key pair used to authenticate API calls.

```bash
mkdir -p ~/.oci

# Generate RSA private key
openssl genrsa -out ~/.oci/oci_api_key.pem 2048

# Derive public key
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem

# Print the fingerprint — save this, you'll need it as OCI_FINGERPRINT
openssl rsa -pubout -outform DER -in ~/.oci/oci_api_key.pem | openssl md5 -c

# Print the public key — you'll paste this into OCI Console
cat ~/.oci/oci_api_key_public.pem

# Print the private key — you'll paste this as the OCI_PRIVATE_KEY secret
cat ~/.oci/oci_api_key.pem
```

---

### Step 3 — Upload the public key to OCI Console

1. Go to: **https://cloud.oracle.com/identity/domains/my-profile/api-keys**  
   *(or: top-right avatar → My Profile → API Keys)*
2. Click **Add API Key**
3. Select **Paste Public Key**
4. Paste the output of `cat ~/.oci/oci_api_key_public.pem`
5. Click **Add**
6. OCI will show a **Configuration File Preview** — note the `fingerprint` value (looks like `aa:bb:cc:dd:...`)

---

### Step 4 — Collect the 8 required values

Open these OCI Console links and copy the OCIDs:

#### 🔑 Tenancy OCID
**Link:** https://cloud.oracle.com/tenancy  
Copy the **OCID** field at the top of the page.  
Looks like: `ocid1.tenancy.oc1..aaaaaaaaxxx`

#### 👤 User OCID
**Link:** https://cloud.oracle.com/identity/domains/my-profile  
*(or: top-right avatar → My Profile)*  
Copy the **OCID** shown at the top.  
Looks like: `ocid1.user.oc1..aaaaaaaaxxx`

#### 🔏 Fingerprint
Shown in the **Configuration File Preview** after uploading your API key in Step 3.  
Also visible at: https://cloud.oracle.com/identity/domains/my-profile/api-keys  
Looks like: `aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99`

#### 🌍 Region identifier
Visible in the OCI Console URL bar — the subdomain before `.oraclecloud.com`.  
Examples: `ap-mumbai-1`, `ap-hyderabad-1`, `us-ashburn-1`, `eu-frankfurt-1`  
Full list: https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm

#### 📦 Compartment OCID
**Link:** https://cloud.oracle.com/identity/compartments  
Click the **root compartment** (your tenancy name) or a child compartment.  
Copy the **OCID** from the detail page.  
Looks like: `ocid1.compartment.oc1..aaaaaaaaxxx`

#### 🌐 Subnet OCID
**Link:** https://cloud.oracle.com/networking/vcns  
1. Click your VCN
2. Click **Subnets** in the left menu
3. Click any **public subnet**
4. Copy the **OCID**  
Looks like: `ocid1.subnet.oc1.ap-mumbai-1.aaaaaaaaxxx`

> If you don't have a VCN yet: Networking → Virtual Cloud Networks → **Start VCN Wizard** → Create VCN with Internet Connectivity

#### 🖼️ Ubuntu 22.04 ARM Image OCID
**Link:** https://cloud.oracle.com/compute/images  
1. Click the **Platform images** tab
2. In the search box type: `Canonical Ubuntu 22`
3. Look for **Canonical Ubuntu 22.04 Minimal** with **OS Version: 22.04 Minimal aarch64**
4. Click the image name → copy the **OCID**  
Looks like: `ocid1.image.oc1.ap-mumbai-1.aaaaaaaaxxx`

---

### Step 5 — Add GitHub Secrets

**Link:** https://github.com/thriftykapila/oci-claim/settings/secrets/actions

Click **New repository secret** for each one:

| Secret Name | Value | Where to get it |
|---|---|---|
| `OCI_TENANCY_OCID` | `ocid1.tenancy.oc1..aaa...` | Step 4 → Tenancy |
| `OCI_USER_OCID` | `ocid1.user.oc1..aaa...` | Step 4 → User OCID |
| `OCI_FINGERPRINT` | `aa:bb:cc:...` | Step 3 → after uploading key |
| `OCI_PRIVATE_KEY` | Full `-----BEGIN RSA PRIVATE KEY-----` content | `cat ~/.oci/oci_api_key.pem` |
| `OCI_REGION` | `ap-mumbai-1` | Step 4 → Region |
| `OCI_COMPARTMENT_ID` | `ocid1.compartment.oc1..aaa...` | Step 4 → Compartment |
| `OCI_SUBNET_ID` | `ocid1.subnet.oc1...` | Step 4 → Subnet |
| `OCI_IMAGE_ID` | `ocid1.image.oc1...` | Step 4 → Image |
| `OCI_SSH_PUBLIC_KEY` | Contents of `~/.ssh/id_rsa.pub` | `cat ~/.ssh/id_rsa.pub` |
| `NTFY_URL` | `https://ntfy.sh/your-topic` | Step 6 (optional) |

---

### Step 6 — Set up phone notifications (optional but recommended)

Get notified the instant the instance is claimed — even at 3am.

1. Install the **ntfy** app: [iOS](https://apps.apple.com/app/ntfy/id1625396347) / [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
2. Pick a **unique secret topic name** — any random string, e.g. `xeli-oci-claim-82931`
3. In the app: tap **+** → subscribe to your topic name
4. Add the secret to GitHub:
   - Secret name: `NTFY_URL`
   - Value: `https://ntfy.sh/xeli-oci-claim-82931`

---

### Step 7 — Enable GitHub Actions

1. Go to: **https://github.com/thriftykapila/oci-claim/actions**
2. Click **I understand my workflows, go ahead and enable them**
3. The workflow will run on its own every 5 minutes via cron

You can also trigger it **immediately** without waiting:  
Actions → **Claim OCI A1 Instance** → **Run workflow** → **Run workflow**

---

## What to expect

Every 5 minutes you'll see a workflow run in the Actions tab.

**While waiting (capacity unavailable):**
```
[2026-07-23 10:00:01] Fetching availability domains...
[2026-07-23 10:00:02] ADs: AP-MUMBAI-1-AD-1 AP-MUMBAI-1-AD-2 AP-MUMBAI-1-AD-3
[2026-07-23 10:00:03] Trying AD: AP-MUMBAI-1-AD-1
[2026-07-23 10:00:04]   Out of capacity in AP-MUMBAI-1-AD-1
[2026-07-23 10:00:05] Trying AD: AP-MUMBAI-1-AD-2
[2026-07-23 10:00:06]   Out of capacity in AP-MUMBAI-1-AD-2
[2026-07-23 10:00:07] All ADs tried. GitHub Actions will retry in 5 minutes.
```

**When claimed:**
```
[2026-07-23 14:32:01] Trying AD: AP-MUMBAI-1-AD-3
[2026-07-23 14:32:03] ==================================================
[2026-07-23 14:32:03] ✅  INSTANCE CLAIMED SUCCESSFULLY!
[2026-07-23 14:32:03]    Instance ID : ocid1.instance.oc1.ap-mumbai-1.xxxxx
[2026-07-23 14:32:03]    AD          : AP-MUMBAI-1-AD-3
[2026-07-23 14:32:03]    Name        : xeli-a1-staging
[2026-07-23 14:32:03] ==================================================
```

Your phone will buzz immediately via ntfy.

---

## After claiming

### Get the public IP (~2 minutes after claim)

```bash
# Install OCI CLI if needed
brew install oci-cli

# Get IP
oci compute instance list-vnics \
  --instance-id ocid1.instance.oc1... \
  --query 'data[0]."public-ip"'
```

Or in the OCI Console:  
**https://cloud.oracle.com/compute/instances** → click your instance → **Instance Details** → **Primary VNIC** → Public IP

### SSH into the new instance

```bash
ssh ubuntu@<PUBLIC-IP>
```

### Disable the workflow (so it stops running)

**https://github.com/thriftykapila/oci-claim/actions/workflows/claim.yml**  
Click the **...** menu → **Disable workflow**

---

## Troubleshooting

| Error | Fix |
|---|---|
| `401 NotAuthenticated` | Double-check `OCI_FINGERPRINT` matches what OCI shows after uploading the key |
| `404 NotFound` for image | The `OCI_IMAGE_ID` is region-specific — make sure it matches your `OCI_REGION` |
| `400 InvalidParameter` for subnet | The subnet must be in the same region as `OCI_REGION` |
| Workflow not running | Go to Actions tab and enable workflows |
| No phone notification | Verify you subscribed to the exact same topic in the ntfy app |
