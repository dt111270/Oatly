# Oatly auto-update (Sparkle) — one-time setup

Goal: Oatly on the Mac updates itself from **GitHub Releases**, silently in the background — same recipe as OhDelhi (see `[[2026-06-25 07-37 OhDelhi deterministic Amazon parser + Sparkle auto-update]]`). After this is set up, shipping a new version is just `./release/release.sh 1.1 2`.

The Swift code is already in place (`Updater.swift` + the `SPUStandardUpdaterController` wired into `OTApp.swift`, `CommandGroup(after: .appInfo)`). What's left is the package, the keys, the GitHub repo, and filling in the script. Work top to bottom.

**Sequencing note:** the plan is to get this whole pipeline working and ship it once by hand, *then* land the MMUtil→Leonai hostname rename fix (`TaskStore.writeToiCloud()`'s `hostName == "MMUtil.local"` check) as the first real release shipped *through* Sparkle — that doubles as the proof the update loop works, so there's no need for a separate throwaway test version.

---

## 0. Check the scheme exists

The project's scheme bookkeeping (`xcschememanagement.plist`) still references schemes named `Oatly` and `OT` that don't currently exist as real `.xcscheme` files — leftover from the OT→Oatly rename (same family of issue as the "phantom Xcode targets" gotcha already logged in Oatly Context.md). `release.sh` needs a real **shared** scheme called `Oatly` targeting the Mac app.

In Xcode: **Product ▸ Scheme ▸ Manage Schemes…** — if there's no `Oatly` scheme for the Mac target, select it (or create one via **New Scheme…**, target = `Oatly`), then tick **Shared**. Without this, `xcodebuild -scheme Oatly archive` in step 7 fails immediately.

## 1. Put Oatly on GitHub

Done already, locally: `git init`, `.gitignore`, and two commits are in place (the Sparkle plumbing, then a follow-up that removed a stray leftover nested `.git` from inside `Oatly/Oatly/` — an old, disconnected 6-commit experiment from April/May that never had a remote — so the real source is tracked cleanly). All that's left is creating the GitHub repo and pushing:

```
cd "~/path/to/Oatly"
gh repo create Oatly --public --source=. --push
```

Note: **must be public**, same as OhDelhi — Sparkle fetches the appcast and release zips over anonymous HTTPS, so a private repo returns "Not Found" (this bit OhDelhi's first attempt). Have a quick look through the source first if that's a concern; Oatly is a personal task manager with no embedded secrets, same profile as OhDelhi.

## 2. Add Sparkle (Swift Package Manager)

The project file already declares the Sparkle package reference (`https://github.com/sparkle-project/Sparkle`, up to next major from 2.9.3) — this was added by editing `project.pbxproj` directly rather than through Xcode's UI, so **the first time you open the project, Xcode needs to resolve it**: File ▸ Packages ▸ Resolve Package Versions (or it may resolve automatically on open — check the Package Dependencies list in the project navigator to confirm Sparkle shows up with a resolved version).

If for any reason it doesn't resolve cleanly, fall back to: remove the broken reference and re-add via **File ▸ Add Package Dependencies…** → URL `https://github.com/sparkle-project/Sparkle` → "Up to Next Major" from **2.9.3** → add to the **Oatly** (Mac) target.

## 3. Generate the EdDSA signing keys

**Important: Oatly needs its own key pair, separate from OhDelhi's.** Sparkle's `sign_update` tool signs with whichever private key is in your keychain — if you reuse OhDelhi's, you'd need to juggle keychain entries per app. Generate a fresh pair:

```
./bin/generate_keys
```

(Same `bin/generate_keys` from the Sparkle release tarball used for OhDelhi — no need to re-download if you kept it.)

- Stores the **private** key in your login keychain (never commit it) — you'll get a second keychain item alongside OhDelhi's.
- Prints the **public** key (base64) — copy it into `Oatly/Info.plist`, replacing the placeholder value of `SUPublicEDKey` (currently `PASTE_PUBLIC_KEY_FROM_generate_keys_HERE`).

## 4. Info.plist — already done, just needs your key + repo slug

`Oatly/Info.plist` already exists with:

| Key | Value |
|-----|-------|
| `SUFeedURL` | `https://raw.githubusercontent.com/dt111270/Oatly/main/release/appcast.xml` |
| `SUPublicEDKey` | *(placeholder — replace with step 3's output)* |
| `SUEnableAutomaticChecks` | `YES` |
| `SUAutomaticallyUpdate` | `YES` ← silent install, no prompting |
| `SUScheduledCheckInterval` | `3600` (hourly) |

If your GitHub username differs from `dt111270`, update the URL in both `Info.plist` and `release/release.sh`'s `GITHUB_REPO`.

> Sparkle requires the app **not** be sandboxed. Oatly's `ENABLE_APP_SANDBOX = NO` and `ENABLE_HARDENED_RUNTIME = YES` are already set correctly (same as OhDelhi).

## 5. notarytool credentials

You already have `ohdelhi-notary` stored from the OhDelhi setup — same Apple ID and Team ID (`9RRVXTX543`), so you can either reuse that profile name in `release.sh` or create a separate one for clarity:

```
xcrun notarytool store-credentials "oatly-notary" \
  --apple-id "your@appleid" --team-id "9RRVXTX543" --password "app-specific-password"
```

The profile name must match `NOTARY_PROFILE` in `release.sh` (defaults to `oatly-notary`).

## 6. Fill in the config

- `release/ExportOptions.plist` — Team ID already set to `9RRVXTX543` (matches Oatly's `DEVELOPMENT_TEAM`). Nothing to change unless that ever differs.
- `release/release.sh` — confirm `GITHUB_REPO`, `NOTARY_PROFILE`, `MIN_MACOS` (currently `26.3`, matching Oatly's `MACOSX_DEPLOYMENT_TARGET`), and `SPARKLE_SIGN` (path to `sign_update` — defaults to `~/bin/sign_update`, same as OhDelhi).
- `chmod +x release/release.sh`

## 7. Ship a release

```
./release/release.sh 1.1 2
```

(Adjust version/build to whatever's next after the current manually-built version.) It archives → notarises → staples → Sparkle-signs → prepends to `appcast.xml` → creates GitHub release `v1.1` with the zip → commits + pushes the appcast.

## 8. First-time install + test

- Copy this first Sparkle-aware build to `/Applications` on the Mac **by hand**, once — the auto-updater can't bootstrap itself onto a machine that doesn't already have a Sparkle-aware build. This is the *last* manual copy Oatly should ever need.
- The **next** release (e.g. the hostname rename fix, `1.2`/`3`) should go out via `release.sh` only. Within `SUScheduledCheckInterval`, the Mac should download and silently update, relaunching itself — or trigger it immediately via the app's new **Check for Updates…** menu item (Oatly menu, right under About).

After this, the deploy-by-hand dance is gone for Oatly too: bump the version, run `release.sh`, done.
