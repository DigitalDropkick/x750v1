# Orbit for iPhone — private beta

Orbit is a native SwiftUI connection screen and WKWebView companion for the
Digital Dropkick GL-X750 console. The shared router interface supplies the full
tool library, schemas, native jobs, input uploads and results. Native code adds
HTTPS certificate binding, iPhone Keychain sign-in, workspace unlocking and
download sharing. It does not run the Linux tools on the phone.

Status: implementation under validation. A successful simulator run does not
establish real-device Face ID, local-network permissions, Wi-Fi/Tailscale
roaming, or attached-hardware compatibility. No signed install is included yet.

## Build without owning a Mac

The `Orbit iPhone validation` GitHub Actions workflow uses a standard macOS
runner to compile and run unit/UI tests. It needs no Apple signing secrets and
does not distribute an app. Standard runners in this public repository are
covered by GitHub's public-repository Actions policy.

An install on an iPhone still requires Apple signing. For this single-device
beta, an Apple Developer Program membership plus a registered-device Ad Hoc
profile provides a private distribution route. TestFlight is another option,
with expiring beta builds. Enrollment and signing are separate from compiling
the source. Never commit a signing key, certificate private key, provisioning
profile or router credential. Do not paste these into chat or build logs.

On a Mac or macOS runner:

```sh
python3 ios/generate-project.py
xcodebuild test -project ios/Orbit.xcodeproj -scheme Orbit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO
```

The Xcode project is checked in. Generation uses Python's standard library;
the app uses Apple frameworks without third-party packages. Minimum target is
iOS 18; the intended acceptance device is Addam's iPhone 17 Pro Max on iOS 26.
Confirm its exact version in Settings → General → About before acceptance.

## Connection design

1. Choose the router Wi-Fi or Tailscale HTTPS address. The iPhone must already
   have access to that route; the app does not silently change Wi-Fi or VPNs.
2. Verify the presented certificate SHA-256 against the router's trusted
   installation record. The public certificate fingerprint can be obtained
   through the existing authenticated SSH connection:
   `openssl x509 -inform DER -in /etc/uhttpd.crt -noout -fingerprint -sha256`.
3. Enter the LuCI username/password on the phone. Sign-in uses the existing
   LuCI endpoint over the verified HTTPS connection. Optional saved sign-in
   uses a device-only Keychain item requiring user presence.
4. Navigate the same tool library and jobs through the Orbit presentation.
   Reconnecting opens the previous job URL and never repeats a tool request.
5. Native file downloads stream into a protected temporary directory, then
   open the iPhone share sheet. Save to Files to retain a phone copy. The
   original artifacts remain on the router according to its retention rules.

Certificates are bound to the exact HTTPS origin. A changed certificate
requires a fresh explicit verification. Redirects and console navigation
remain on that origin. No password is embedded in JavaScript, a URL, a plist,
a repository setting, or a log. The existing router session and action ACLs
remain responsible for authorization.

## Shared interface preview

After installing the companion assets on the router, append `?orbit=1` to a
console route, for example `/cgi-bin/luci/admin/ddk/overview?orbit=1`.
The mode follows internal navigation in that browser session. `?orbit=0`
returns to the standard dashboard appearance. Native Orbit selects its mode
with its own user-agent suffix. All five console pages remain available.

Safari can add the Orbit page to the Home Screen. This is a browser preview
with LuCI browser sign-in, not the signed native app or its Keychain feature.
It does not promise offline execution or cache authenticated responses.

## Rollback

Native source and its workflow are isolated under `ios/` and the Orbit workflow.
Use the router deployment's printed backup with the existing `rollback.sh` to
restore its previous application files. Saved cases and inputs are retained.
Changing or uninstalling the iPhone app does not stop or delete router jobs.
