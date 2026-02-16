# CurseForge Deployment Plan — AltArmy TBC

This plan covers two ways to deploy: **CurseForge webhook (simplest)** and **GitHub Actions (more control)**. You can choose one.

---

## Prerequisites (both approaches)

1. **CurseForge project**
   - Create the project on [CurseForge](https://www.curseforge.com/) for WoW Classic (TBC) if you haven’t already.
   - Note the **Project ID** from the project’s **About This Project** section on the Overview page.

2. **CurseForge API token**
   - Go to [API tokens](https://www.curseforge.com/account/api-tokens).
   - Create a token (e.g. name: “Webhooks” or “GitHub Actions”).
   - Save it securely; you’ll use it in GitHub (secret or webhook URL).

3. **Game version**
   - Your TOC uses `## Interface: 20502` (TBC Classic). Use the matching **Game Version** ID(s) from CurseForge — see **Where to get game version IDs** below.

---

## Where to get game version IDs

CurseForge’s website doesn’t show numeric version IDs when you upload a file; it only shows names (e.g. “Burning Crusade Classic”) in the dropdown. The upload API needs the **numeric ID** for each game version.

**Use the Game Versions API (WoW):**

1. Open [CurseForge API tokens](https://www.curseforge.com/account/api-tokens) and copy your token (or create one).
2. In a terminal, run (replace `YOUR_API_TOKEN` with your token):

   ```bash
   curl -s -H "X-Api-Token: YOUR_API_TOKEN" "https://wow.curseforge.com/api/game/versions"
   ```

   That returns JSON: an array of objects with `id`, `name`, `slug`, and sometimes `gameVersionTypeID`. Each object is one selectable “game version” (e.g. a WoW or WoW Classic patch).

3. Find the row(s) that match **TBC Classic** (or “Burning Crusade Classic” / whatever CurseForge calls it for Interface 20502). Use the **`id`** value(s).
4. For **CURSEFORGE_GAME_VERSIONS** in GitHub, enter those IDs as a comma-separated list, e.g. `1234,5678` (no spaces, or spaces are fine — the workflow trims them).

**Optional — pretty-print to find TBC:**  
If you have `jq`, you can list only `id` and `name` to scan quickly:

```bash
curl -s -H "X-Api-Token: YOUR_API_TOKEN" "https://wow.curseforge.com/api/game/versions" | jq '.[] | {id, name}'
```

Search the output for “TBC”, “Burning Crusade”, or “Classic” and use the `id`(s) you need.

---

## Option A: CurseForge repository webhook (simplest)

CurseForge builds and packages when you push; you configure what goes in the package with a file in the repo.

### Steps

1. **Add `pkgmeta.yaml` in the repo root**  
   Tells CurseForge how to package and what to ignore.

   - **package-as:** `AltArmy_TBC` (or your desired package name).
   - **ignore:** Paths that must not be in the zip, e.g.:
     - `spec/`
     - `scripts/`
     - `busted-2.1.1/`
     - `luacheck-src/`
     - `node_modules/` (if you add it later)
     - `docs/` (optional, if you don’t want internal docs in the zip)
     - `.git/`, `.cursor/`, etc. (often ignored by default; confirm in [CurseForge docs](https://support.curseforge.com/support/solutions/articles/9000197281-automatic-packaging)).
   - **optional:** `license-output`, `manual-changelog`, `required-dependencies` / `optional-dependencies` if you use them.

2. **Add GitHub webhook**
   - Repo → **Settings** → **Webhooks** → **Add webhook**.
   - **Payload URL:**  
     `https://www.curseforge.com/api/projects/{projectID}/package?token={token}`  
     Replace `{projectID}` and `{token}` with your CurseForge project ID and API token.
   - Leave other settings as default (e.g. Just the push event).

3. **Release type (alpha / beta / release)**
   - **Tagged commits:** tag name controls type:
     - Tag contains `alpha` → Alpha.
     - Tag contains `beta` → Beta.
     - Otherwise → Release.
   - **Untagged (e.g. push to `main`):** treated as Alpha (if you have “package all commits” enabled).

4. **Trigger a build**
   - Push to the branch you connected, or push a tag (e.g. `1.0.0`, `1.0.0-beta`, `1.0.0-alpha`).

**Pros:** No workflow file to maintain; CurseForge does packaging.  
**Cons:** Less control over exact zip contents; depends on CurseForge’s packager and pkgmeta support.

---

## Option B: GitHub Actions (like Altoholic)

You build the zip in GitHub Actions and upload it via the CurseForge upload API. Full control over what’s in the zip.

### Steps

1. **GitHub secrets and variables**
   - **Secrets (Settings → Secrets and variables → Actions):**
     - `CURSEFORGE_API_TOKEN`: your CurseForge API token.
   - **Variables (same place):**
     - `CURSEFORGE_PROJECT_ID`: CurseForge project ID.
     - `CURSEFORGE_DISPLAY_NAME`: e.g. `AltArmy TBC` (used in “display name” of the file).
     - `CURSEFORGE_GAME_VERSIONS`: comma-separated list of CurseForge game version IDs for TBC Classic (e.g. `1234,5678` — get IDs from CurseForge).

2. **Add workflow file**
   - Create `.github/workflows/release.yml` (or `curseforge-release.yml`).
   - **Trigger:** e.g. `push` to `main` and/or `workflow_dispatch` (manual).
   - **Steps:**
     1. **Checkout** repo.
     2. **Extract version** from `AltArmy_TBC/AltArmy_TBC.toc` (e.g. line `## Version: 0.0.1` → `0.0.1`).
     3. **Build zip:**
        - Include only what players need (e.g. `AltArmy_TBC/` and its contents).
        - Exclude: `spec/`, `scripts/`, `busted-2.1.1/`, `luacheck-src/`, `node_modules/`, `.git/`, `docs/`, etc.
        - Zip so the archive contains the folder `AltArmy_TBC/` (so users extract to `Interface/AddOns/` and get `Interface/AddOns/AltArmy_TBC/...`).
     4. **Upload to CurseForge** with `curl` (or a dedicated action if you prefer):
        - `POST` to `https://wow.curseforge.com/api/projects/{projectId}/upload-file` (or the URL shown in current CurseForge API docs).
        - Headers: `x-api-token: <CURSEFORGE_API_TOKEN>`.
        - Body: multipart with `metadata` (JSON: `displayName`, `gameVersions`, `releaseType`, `changelog`) and `file` (the zip).
   - Use the Altoholic workflow as a reference for the exact API shape and env vars:  
     [Altoholic_Vanilla release.yml](https://github.com/Thaoky/Altoholic_Vanilla/blob/main/.github/workflows/release.yml).

3. **Release type in metadata**
   - In the upload step, set `releaseType` to `alpha`, `beta`, or `release` (e.g. from branch name, tag, or a fixed value for now).

4. **Changelog**
   - Either a static message in `metadata.changelog`, or a file (e.g. `CHANGELOG.txt`) read in the workflow and sent in the request.

5. **Run**
   - Push to `main` or run the workflow manually from the Actions tab.

**Pros:** Full control over zip contents and version/changelog; no reliance on CurseForge packager.  
**Cons:** You maintain the workflow and any changes to the CurseForge API.

### Option B — Implemented

The workflow **`.github/workflows/release.yml`** is in place. Do the following to finish setup:

1. **GitHub → Settings → Secrets and variables → Actions**
   - **New repository secret:** Name `CURSEFORGE_API_TOKEN`, value = your CurseForge API token.
   - **New repository variable:** Name `CURSEFORGE_PROJECT_ID`, value = CurseForge project ID (numeric).
   - **New repository variable:** Name `CURSEFORGE_DISPLAY_NAME`, value = e.g. `AltArmy TBC` (used as the file display name).
   - **New repository variable:** Name **exactly** `CURSEFORGE_GAME_VERSIONS` (no commas or spaces in the name). Value = comma-separated game version IDs, e.g. `8660` or `8660,8924,9049,14300`.  
     GitHub only allows letters, numbers, and underscores in secret/variable **names**; the comma-separated list is the **value**. See **Where to get game version IDs** above for how to get the IDs.

2. **Optional:** Add **`CHANGELOG.txt`** in the repo root. If present, its contents are sent as the file changelog; otherwise the workflow uses *"See repository for changes."*.

3. **How it runs**
   - **Push to `main`:** version from `AltArmy_TBC.toc`, release type **alpha**.
   - **Push a tag** (e.g. `v1.0.0`, `1.0.0-beta`): version from the tag; release type **release** (or **beta** if tag contains `beta`, **alpha** if tag contains `alpha`).
   - **Manual run (Actions → CurseForge Release → Run workflow):** choose **release** / **beta** / **alpha**; version still from TOC (or from tag if you run on a tag ref).

4. **First test:** Run the workflow manually (workflow_dispatch) after saving the secret and variables. Fix any missing or wrong variable values before relying on push/tag.

---

## Recommendation

- Prefer **Option A** if you want minimal setup and are fine with CurseForge’s packaging and pkgmeta.
- Prefer **Option B** if you want to guarantee only `AltArmy_TBC/` (and no `spec/`, `scripts/`, or dev tools) are in the zip and to drive version/display name from the TOC.

---

## Checklist (summary)

- [ ] CurseForge project created; Project ID noted.
- [ ] CurseForge API token created and stored safely.
- [ ] Game version ID(s) for TBC Classic (Interface 20502) noted from CurseForge.
- [ ] **Option A:** `pkgmeta.yaml` added; webhook added on GitHub; test push/tag.
- [x] **Option B:** `.github/workflows/release.yml` added (zip includes only `AltArmy_TBC/`).
- [ ] **Option B:** Secrets and variables set in GitHub; run workflow once (e.g. manually) to verify.

---

## References

- [CurseForge automatic packaging](https://support.curseforge.com/support/solutions/articles/9000197281-automatic-packaging) — webhook, pkgmeta, tokens, alpha/beta/release.
- [Altoholic_Vanilla release workflow](https://github.com/Thaoky/Altoholic_Vanilla/blob/main/.github/workflows/release.yml) — example of zip + CurseForge upload via API.
