# Signing & Notarization (Milestone B)

MacPilot ships a native macOS app. Local builds are **unsigned** and will
trigger a Gatekeeper warning. To distribute a build that opens cleanly on
other Macs, sign it with an Apple Developer ID and notarize it.

## One-time setup

1. Enroll in the Apple Developer Program and create a
   **Developer ID Application** certificate in Xcode → Settings → Accounts.
2. Create a notarytool profile (only once):

   ```bash
   xcrun notarytool store-credentials macpilot \
     --apple-id "you@example.com" \
     --team-id "TEAMID" \
     --password "app-specific-password"
   ```

   (Use an App-Specific Password, not your Apple ID password.)

3. Find your signing identity:

   ```bash
   security find-identity -v -p codesigning
   # look for: "Developer ID Application: Your Name (TEAMID)"
   ```

## Build a signed + notarized DMG

```bash
NOTARY_PROFILE="macpilot" \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
  scripts/package.sh
```

The script builds Release, codesigns with the hardened runtime
(`--options runtime`), submits for notarization, staples the ticket, and
wraps the app in a DMG under `dist/`.

## Verify the result

```bash
spctl --assess --type execute -vvv dist/MacPilotDemo.app
xcrun stapler validate dist/MacPilotDemo.app
```

`spctl` should report `accepted` / `source=Notarized Developer ID`.

## Unsigned fallback

With no environment variables set, `scripts/package.sh` still produces a
working `dist/MacPilotDemo-<version>.dmg`, just unsigned. It is fine for
personal testing and demos.
