# Install Orbit on your iPhone

You do **not** have to buy an Apple Developer Program membership to try Orbit.
The free route uses your Apple Account to sign the compiled app with
[iloader](https://iloader.app/) and [SideStore](https://docs.sidestore.io/docs/installation/prerequisites).
These are third-party tools, separate from Apple's TestFlight. No Mac is needed
on your desk: GitHub's macOS runner compiles the app and signing happens during
installation. Apple credentials never belong in this repository or GitHub CI.

## Choose the installation route

| Route | Cost | What you maintain |
| --- | --- | --- |
| Safari Home Screen preview | Free | Normal LuCI browser sign-in; no native Keychain/Face ID connection screen |
| Native Orbit through SideStore | Free | Refresh Orbit **and SideStore** before their seven-day expiry; Wi-Fi and LocalDevVPN are needed for refresh |
| Native Orbit through TestFlight | Apple Developer Program: $99 USD/year | Developer enrollment and signed upload setup; TestFlight builds expire after 90 days |

Free signing allows three active development apps, including SideStore. Orbit
has no extensions and uses one slot. Expiry affects opening the iPhone app;
it does not stop jobs already running on the router. Refresh before field work.
Do not depend solely on automatic background refresh.

Sources: [Apple free account limits](https://developer.apple.com/help/account/basics/about-your-developer-account),
[SideStore limits](https://docs.sidestore.io/docs/faq),
[Apple enrollment and price](https://developer.apple.com/programs/enroll/),
[TestFlight](https://developer.apple.com/testflight/).

## Free installation from this Linux laptop

1. On the iPhone, check **Settings → General → About → iOS Version**. Orbit
   targets iOS 18 or newer. Keep the phone's normal passcode enabled.
2. Install **LocalDevVPN** from the App Store using the link in the
   [official SideStore prerequisites](https://docs.sidestore.io/docs/installation/prerequisites).
   Use Wi-Fi with internet access during installation and refresh.
3. Connect the unlocked iPhone to the laptop with a USB data cable. Tap
   **Trust This Computer** on the phone and enter its passcode there.
4. Launch the prepared Linux installer:

   ```sh
   /home/astro/Downloads/Orbit-Beta/Launch-iPhone-Installer.sh
   ```

   The official iloader 2.3.3 AppImage was downloaded and its SHA-256 matched
   GitHub's release asset digest. It was extracted beside the launcher to avoid
   requiring FUSE or a system installation. The laptop already has `usbmuxd`
   and `libimobiledevice-utils`; USB discovery still needs the connected phone.
5. In iloader, sign in with an Apple Account **inside its window**, complete
   Apple's verification prompts, and select your phone. A separate free Apple
   Account may be used. Choose **Install SideStore (Stable)**.
6. Follow the current [SideStore installation steps](https://docs.sidestore.io/docs/installation/install):
   trust the developer app under **Settings → General → VPN & Device Management**;
   allow the requested restart; enable **Settings → Privacy & Security →
   Developer Mode** and confirm its restart.
7. Open LocalDevVPN and connect. Open SideStore, sign in using the same account,
   then go to **My Apps** and refresh **SideStore itself first** using its day
   counter. Complete any signing-certificate prompt in SideStore.
8. Get Orbit's build from the successful
   [Orbit iPhone validation run](https://github.com/DigitalDropkick/x750v1/actions).
   Download the **orbit-unsigned-iphone** artifact. GitHub may ask you to sign in
   to download an Actions artifact. In iPhone Files, extract the downloaded ZIP;
   the app file inside is **Orbit-unsigned.ipa**.
9. In SideStore's **My Apps**, use **+** to choose that IPA from Files. SideStore
   signs it for your account and installs it. The IPA is intentionally unsigned
   when it leaves GitHub; simply tapping it in Safari will not install it.
10. Open **Orbit** from your Home Screen and follow the first connection below.

If you prefer an initial USB-only trial, iloader can directly install the Orbit
IPA without SideStore. That simpler route requires returning to the laptop to
sign/install it again before its free profile expires.

When refreshing with SideStore, temporarily use LocalDevVPN. Afterwards turn it
off and reconnect Tailscale if you use the router's remote address. iOS restricts
simultaneous VPN connections; a refresh should not be mistaken for an active
Tailscale connection. [Tailscale VPN guidance](https://tailscale.com/docs/reference/faq/other-vpns)

Do not send Apple sign-in details, verification codes, signing keys or device
pairing files through chat. No Apple account has been entered by the build agent.

## First native connection

1. Join the router Wi-Fi, then choose **Router Wi-Fi** in Orbit. This uses
   `https://192.168.8.1`. For remote access, connect the Tailscale app first and
   choose **Tailscale**, which uses `https://100.122.115.85`.
2. Tap **Connect to router**. On first pairing, compare the certificate
   fingerprint with the [trusted router record](ORBIT-BETA.md#router-certificate-identity),
   then tap **Fingerprint verified · trust router** if it matches.
3. Enter the router's **LuCI** username/password. This is separate from its Wi-Fi
   password and your Apple Account. Allow Local Network access if iOS asks.
4. Keep **Save sign-in with Face ID / passcode** enabled if wanted. Subsequent
   launches can retrieve the saved login after iPhone authentication.
5. Run a simple workflow first. Check the result and save a report through the
   native share sheet using **Save to Files**. Then try your Android workflow
   with the intended device connected to the router.

The app remembers the selected route. It does not configure Wi-Fi or Tailscale
for you or automatically submit tools when reconnecting. A changed router
certificate requires verification again. Tools execute on the X750, so targets
must be reachable from that router.

## If you want TestFlight instead

Paid membership is optional for this beta. It provides Apple's TestFlight
delivery route, avoiding SideStore's weekly refresh routine and local VPN step.

1. Install **Apple Developer** from the App Store. Open **Account**, sign in
   with an Apple Account with two-factor authentication, then choose **Enroll Now**.
2. For an app owned by you personally, use **Individual**, your legal name and
   the requested identity/contact information. For Digital Dropkick, LLC to own
   the account, choose **Organization**; Apple also verifies the legal entity,
   D-U-N-S number, authority and business website/contact details.
3. Complete Apple's identity review, accept the agreement and pay the displayed
   annual price if you decide to enroll. Enrollment in the app is an annual
   subscription; review the renewal terms.
4. Once Apple shows the membership as active, we can configure the private
   signing/upload workflow and App Store Connect beta. Enrollment alone does
   not upload or install Orbit. No signing secrets have been created or stored
   in GitHub yet.

[Apple's enrollment instructions](https://developer.apple.com/help/account/membership/enrolling-in-the-app)

## Acceptance and rollback

Cloud simulator tests are separate from acceptance on your actual iPhone.
Still check Face ID/passcode, Local Network permission, Wi-Fi/Tailscale access,
interrupted sessions, Files import/export, and your attached hardware.

Removing the phone app does not delete router jobs or cases. Reinstall the same
app with the same signing identity when updating if you want to preserve local
preferences. The browser preview stays available at `/ddk`; its router rollback
is documented in [the beta record](ORBIT-BETA.md#rollback).
