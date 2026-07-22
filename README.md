# OCI A1 Auto-Claim

Automatically claims an Oracle Cloud **Always Free** Ampere A1 instance (4 OCPU / 24 GB RAM) using GitHub Actions — no server or Mac required.

Runs every **5 minutes** via GitHub's free infrastructure and sends a **push notification** the moment capacity is available.

## How it works

1. GitHub Actions cron triggers every 5 minutes (free on public repos)
2. Attempts to launch `VM.Standard.A1.Flex` across all availability domains
3. If Oracle returns "Out of host capacity" → sleeps and retries
4. When claimed → sends push notification via [ntfy.sh](https://ntfy.sh) + stops the workflow

## Setup

### 1. Fork or use this repo (must be public for free minutes)

### 2. Add GitHub Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret**

| Secret name | Value |
|---|---|
| `OCI_TENANCY_OCID` | `ocid1.tenancy.oc1..aaaaa...` |
| `OCI_USER_OCID` | `ocid1.user.oc1..aaaaa...` |
| `OCI_FINGERPRINT` | `xx:xx:xx:xx:...` (from OCI Console after uploading API key) |
| `OCI_PRIVATE_KEY` | Full contents of `~/.oci/oci_api_key.pem` |
| `OCI_REGION` | e.g. `ap-mumbai-1` |
| `OCI_COMPARTMENT_ID` | `ocid1.compartment.oc1..aaaaa...` |
| `OCI_SUBNET_ID` | `ocid1.subnet.oc1...` |
| `OCI_IMAGE_ID` | `ocid1.image.oc1...` (Ubuntu 22.04 aarch64) |
| `OCI_SSH_PUBLIC_KEY` | Contents of your `~/.ssh/id_rsa.pub` |
| `NTFY_URL` | `https://ntfy.sh/your-secret-topic` (optional, for phone alerts) |

### 3. Enable Actions

Go to the **Actions** tab → enable workflows.

### 4. Get notified

Install [ntfy](https://ntfy.sh) on your phone and subscribe to your chosen topic. You'll get a push notification the moment the instance is claimed.

## Finding your OCIDs

- **Tenancy OCID**: OCI Console → Hamburger → Administration → Tenancy Details
- **User OCID**: Top-right avatar → My Profile → copy OCID
- **Fingerprint**: My Profile → API Keys → (after uploading public key, fingerprint shown)
- **Compartment OCID**: Identity → Compartments → your compartment
- **Subnet OCID**: Networking → VCNs → your VCN → Subnets → click subnet
- **Image OCID**: Compute → Images → Platform Images → Ubuntu 22.04 Minimal → aarch64 → copy OCID

## Generating OCI API Keys

```bash
# Generate key pair
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem

# Get fingerprint
openssl rsa -pubout -outform DER -in ~/.oci/oci_api_key.pem | openssl md5 -c

# Upload the public key to OCI Console:
# My Profile → API Keys → Add API Key → paste contents of oci_api_key_public.pem
cat ~/.oci/oci_api_key_public.pem
```

## Once claimed

The workflow logs will show:
```
✅  INSTANCE CLAIMED SUCCESSFULLY!
   Instance ID: ocid1.instance.oc1...
   AD: AP-MUMBAI-1-AD-1
```

Get the public IP (~2 min after claim):
```bash
oci compute instance list-vnics --instance-id <ID> | grep public-ip
```

Then disable this workflow (Actions → Claim workflow → Disable).
