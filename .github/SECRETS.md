# GitHub Actions Secrets Setup

Configure these secrets in your repository:
**Settings → Secrets and variables → Actions → New repository secret**

---

## Android Signing (optional — debug APKs work without this)

| Secret | Description | How to obtain |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded `.jks` keystore file | `base64 -w0 release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password | Set when creating keystore |
| `ANDROID_KEY_ALIAS` | Key alias inside keystore | Set when creating keystore |
| `ANDROID_KEY_PASSWORD` | Key password | Set when creating keystore |

### Create a release keystore

```bash
keytool -genkey -v \
  -keystore release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storepass YOUR_STORE_PASS \
  -keypass YOUR_KEY_PASS \
  -dname "CN=Flutter VPN Go, OU=Dev, O=Example, L=City, S=State, C=US"

# Encode for GitHub secret:
base64 -w0 release.jks
```

---

## iOS Signing (required for signed IPA — unsigned IPA works for sideloading)

| Secret | Description | How to obtain |
|---|---|---|
| `IOS_CERTIFICATE_BASE64` | Base64-encoded `.p12` distribution cert | Export from Keychain Access |
| `IOS_CERTIFICATE_PASSWORD` | `.p12` export password | Set during export |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64-encoded `.mobileprovision` | Download from developer.apple.com |
| `IOS_TEAM_ID` | 10-character Apple Team ID | developer.apple.com → Account |
| `IOS_KEYCHAIN_PASSWORD` | Temporary keychain password | Any random string |

### Export iOS certificate

1. Open **Keychain Access** on macOS.
2. Find your **Apple Distribution** or **iOS Distribution** certificate.
3. Right-click → **Export** → Choose `.p12` format.
4. Set an export password.
5. Encode: `base64 -w0 certificate.p12`

### Download provisioning profile

1. Go to [developer.apple.com](https://developer.apple.com) → Certificates, IDs & Profiles.
2. Create an **Ad Hoc** or **App Store** distribution profile for your app.
3. Download the `.mobileprovision` file.
4. Encode: `base64 -w0 profile.mobileprovision`

---

## Verification

After setting up secrets, trigger a manual release:

1. Go to **Actions** → **Release** → **Run workflow**
2. Enter a test tag (e.g., `v0.0.1-test`)
3. Check ✅ "Mark as pre-release"
4. Click **Run workflow**

If signing secrets are configured correctly, you'll get a signed APK/IPA.
Without signing secrets, you'll get an unsigned debug build (still sideloadable).

---

## iOS without signing (unsigned IPA for AltStore)

Even without signing secrets, the workflow produces an **unsigned IPA** that
can be installed via [AltStore](https://altstore.io/) or [Sideloadly](https://sideloadly.io/).

This is the recommended approach for personal use and testing.
