#!/usr/bin/env bash
# One-time Google Cloud setup for the hosted app, one section at a time (each creates billable or
# visible resources, so run them deliberately):
#
#   deploy/setup.sh apis         enable the APIs
#   deploy/setup.sh registry     Artifact Registry repo, keeping the last 5 images
#   deploy/setup.sh accounts     service accounts and their roles
#   deploy/setup.sh sql          Cloud SQL instance (Postgres 16, db-f1-micro, 10 GB SSD)
#   deploy/setup.sh database ENV   a database, its user (random password) and the DATABASE_URL secret
#   deploy/setup.sh staging-auth staging's runtime service account (after `database staging` and the
#                                alt-army-staging Firebase project exist; README, "Firebase projects")
#   deploy/setup.sh firestore    Firestore for price signals in prod's and staging's Firebase projects (after
#                                `accounts` and `staging-auth`), and who may write signals and deploy rules
#   deploy/setup.sh wif          Workload Identity Federation for GitHub Actions
#   deploy/setup.sh scheduler ENV  Cloud Scheduler jobs for prod or staging (after a deploy of ENV made its
#                                jobs; existing ones are kept)
#   deploy/setup.sh job-runner ENV  let ENV's service start its ingest jobs (the Admin page's Run now; after
#                                a deploy of ENV made them)
#   deploy/setup.sh alerts EMAIL  an email channel to EMAIL and the alert policies that use it (existing
#                                ones are kept)
#
# Then: BUILDER=cloudbuild deploy/build.sh, deploy/deploy.sh prod|staging IMAGE (README, "Deploy").
set -euo pipefail
cd "$(dirname "$0")/.."
source deploy/config.sh
G=("${GCLOUD_FLAGS[@]}")

apis() {
  gcloud services enable run.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com \
    artifactregistry.googleapis.com cloudscheduler.googleapis.com cloudbuild.googleapis.com \
    iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com "${G[@]}"
}

registry() {
  gcloud artifacts repositories create "$REPO" --repository-format docker --location "$REGION" \
    --description "altarmy-profit images" "${G[@]}"
  gcloud artifacts repositories set-cleanup-policies "$REPO" --location "$REGION" \
    --policy deploy/ar-cleanup.json --no-dry-run "${G[@]}"
}

project_role() { # project_role MEMBER ROLE
  gcloud projects add-iam-policy-binding "$PROJECT" --member "$1" --role "$2" --condition None \
    "${G[@]}" >/dev/null
  echo "  $2 -> $1"
}

accounts() {
  gcloud iam service-accounts create altarmy-run --display-name "altarmy-profit service and jobs" "${G[@]}"
  gcloud iam service-accounts create altarmy-scheduler --display-name "altarmy-profit scheduler" "${G[@]}"
  gcloud iam service-accounts create altarmy-deploy --display-name "altarmy-profit CI deploys" "${G[@]}"

  # runtime: Cloud SQL, its secrets (granted per secret in `database`), deleting Firebase Auth users
  project_role "serviceAccount:$PROD_RUN_SA" roles/cloudsql.client
  project_role "serviceAccount:$PROD_RUN_SA" roles/firebaseauth.admin
  # scheduler: start Cloud Run jobs
  project_role "serviceAccount:$SCHEDULER_SA" roles/run.invoker
  # CI: deploy services and jobs as altarmy-run, push images, deploy Hosting; Cloud Build as itself
  for role in roles/run.admin roles/artifactregistry.writer roles/firebasehosting.admin \
    roles/serviceusage.serviceUsageConsumer roles/logging.logWriter roles/storage.objectViewer; do
    project_role "serviceAccount:$DEPLOY_SA" "$role"
  done
  gcloud iam service-accounts add-iam-policy-binding "$PROD_RUN_SA" --member "serviceAccount:$DEPLOY_SA" \
    --role roles/iam.serviceAccountUser "${G[@]}" >/dev/null
}

sql() {
  gcloud sql instances create "$SQL_INSTANCE" --database-version POSTGRES_16 --edition ENTERPRISE \
    --tier db-f1-micro --region "$REGION" --storage-type SSD --storage-size 10 --storage-auto-increase \
    --availability-type zonal --backup-start-time 08:00 --retained-backups-count 7 \
    --assign-ip "${G[@]}"
}

database() { # database prod|staging: its database, user and DATABASE_URL secret (password never printed)
  env_config "${1:?prod or staging}"
  gcloud sql databases create "$DB_NAME" --instance "$SQL_INSTANCE" "${G[@]}"
  local password
  password="$(openssl rand -hex 24)"
  gcloud sql users create "$DB_USER" --instance "$SQL_INSTANCE" --password "$password" "${G[@]}"
  printf 'postgresql+psycopg://%s:%s@/%s?host=/cloudsql/%s' "$DB_USER" "$password" "$DB_NAME" \
    "$SQL_CONNECTION" | gcloud secrets create "$SECRET" --data-file - --replication-policy automatic "${G[@]}"
  gcloud secrets add-iam-policy-binding "$SECRET" --member "serviceAccount:$RUN_SA" \
    --role roles/secretmanager.secretAccessor "${G[@]}" >/dev/null
}

staging_auth() { # staging's own runtime account: its database secret only, and admin of staging's Auth only
  gcloud iam service-accounts create altarmy-staging-run --display-name "altarmy-profit staging service and jobs" \
    "${G[@]}"
  project_role "serviceAccount:$STAGING_RUN_SA" roles/cloudsql.client
  # deleting accounts (DELETE /api/me) in the staging Firebase project; that project has no billing, so the
  # call bills (nothing) to $PROJECT
  gcloud projects add-iam-policy-binding "$STAGING_AUTH_PROJECT" --member "serviceAccount:$STAGING_RUN_SA" \
    --role roles/firebaseauth.admin --condition None --billing-project "$PROJECT" --quiet >/dev/null
  echo "  roles/firebaseauth.admin on $STAGING_AUTH_PROJECT -> $STAGING_RUN_SA"
  env_config staging
  gcloud secrets add-iam-policy-binding "$SECRET" --member "serviceAccount:$STAGING_RUN_SA" \
    --role roles/secretmanager.secretAccessor "${G[@]}" >/dev/null
  # prod's account read staging's secret while staging ran as it
  gcloud secrets remove-iam-policy-binding "$SECRET" --member "serviceAccount:$PROD_RUN_SA" \
    --role roles/secretmanager.secretAccessor "${G[@]}" >/dev/null 2>&1 || echo "  (prod had no access to $SECRET)"
  gcloud iam service-accounts add-iam-policy-binding "$STAGING_RUN_SA" --member "serviceAccount:$DEPLOY_SA" \
    --role roles/iam.serviceAccountUser "${G[@]}" >/dev/null
}

firestore() { # the price signals' database (signals.py, firestore.rules): one per Firebase project
  local project sa
  for pair in "$PROJECT:$PROD_RUN_SA" "$STAGING_AUTH_PROJECT:$STAGING_RUN_SA"; do
    project="${pair%%:*}" sa="${pair#*:}"
    # staging's project has no billing: every call bills (nothing) to $PROJECT
    gcloud services enable firestore.googleapis.com firebaserules.googleapis.com --project "$project"       --billing-project "$PROJECT" --quiet
    gcloud firestore databases create --location "$REGION" --type firestore-native --project "$project"       --billing-project "$PROJECT" --quiet
    # the service and its jobs write signals; CI deploys the rules
    gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:$sa" --role roles/datastore.user       --condition None --billing-project "$PROJECT" --quiet >/dev/null
    echo "  roles/datastore.user on $project -> $sa"
    gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:$DEPLOY_SA"       --role roles/firebaserules.admin --condition None --billing-project "$PROJECT" --quiet >/dev/null
    echo "  roles/firebaserules.admin on $project -> $DEPLOY_SA"
    # the Firebase CLI checks the Firestore API is enabled before deploying rules
    gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:$DEPLOY_SA"       --role roles/serviceusage.serviceUsageConsumer --condition None --billing-project "$PROJECT" --quiet >/dev/null
    echo "  roles/serviceusage.serviceUsageConsumer on $project -> $DEPLOY_SA"
  done
}

wif() {
  gcloud iam workload-identity-pools create "$WIF_POOL" --location global \
    --display-name "GitHub Actions" "${G[@]}"
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" --location global \
    --workload-identity-pool "$WIF_POOL" --issuer-uri https://token.actions.githubusercontent.com \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition "assertion.repository == '$GITHUB_REPO'" "${G[@]}"
  gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" --role roles/iam.workloadIdentityUser \
    --member "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WIF_POOL/attribute.repository/$GITHUB_REPO" \
    "${G[@]}" >/dev/null
  echo "GitHub repo variables:"
  echo "  GCP_WIF_PROVIDER=projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WIF_POOL/providers/$WIF_PROVIDER"
  echo "  GCP_DEPLOY_SA=$DEPLOY_SA"
}

schedule() { # schedule NAME CRON: run the Cloud Run job NAME on CRON (UTC); skipped if it exists
  if gcloud scheduler jobs describe "$1" --location "$REGION" "${G[@]}" >/dev/null 2>&1; then
    echo "schedule $1 exists"
    return
  fi
  gcloud scheduler jobs create http "$1" --location "$REGION" --schedule "$2" --time-zone Etc/UTC \
    --uri "https://run.googleapis.com/v2/projects/$PROJECT/locations/$REGION/jobs/$1:run" \
    --http-method POST --oauth-service-account-email "$SCHEDULER_SA" \
    --oauth-token-scope https://www.googleapis.com/auth/cloud-platform "${G[@]}"
}

scheduler() { # scheduler prod|staging: the same cadence (jobs.CADENCE); staging's a few minutes after prod's,
  # so the two never run at once on the shared Cloud SQL instance
  env_config "${1:?prod or staging}"
  local m=0
  [ "$1" = staging ] && m=5
  schedule "$JOB_PREFIX-ingest-tbc" "$((0 + m)) 9 * * *"
  schedule "$JOB_PREFIX-ingest-forever" "$((15 + m)) 9 * * *"
  schedule "$JOB_PREFIX-prune" "$((0 + m)) 10 * * *"
  schedule "$JOB_PREFIX-merge" "$((30 + m)) * * * *" # hourly: daily medians and 7-day price statistics
}

job_runner() { # job-runner prod|staging: the service may start its ingest jobs (the Admin page's Run now)
  env_config "${1:?prod or staging}"
  local job
  for job in "$JOB_PREFIX-ingest-tbc" "$JOB_PREFIX-ingest-forever"; do
    gcloud run jobs add-iam-policy-binding "$job" --region "$REGION" --member "serviceAccount:$RUN_SA" \
      --role roles/run.invoker "${G[@]}" >/dev/null
    echo "  roles/run.invoker on $job -> $RUN_SA"
  done
}

alerts() { # alerts EMAIL: log-based alert policies (a job's `Run.warn`), emailed at most once a day
  local email="${1:?an email address to notify}" channel policy file
  channel="$(gcloud beta monitoring channels list --filter "type=\"email\" AND labels.email_address=\"$email\"" \
    --format 'value(name)' "${G[@]}" | head -n 1)"
  if [ -z "$channel" ]; then
    channel="$(gcloud beta monitoring channels create --type email --display-name "altarmy alerts ($email)" \
      --channel-labels "email_address=$email" --format 'value(name)' "${G[@]}")"
  fi
  echo "  notification channel $channel"

  # merge.PARTITION_ALERT: price_observations is past merge.PARTITION_AT rows (prod's or staging's merge)
  policy="altarmy price_observations needs partitioning"
  if gcloud alpha monitoring policies list --filter "displayName=\"$policy\"" --format 'value(name)' \
    "${G[@]}" | grep -q .; then
    echo "policy '$policy' exists"
    return
  fi
  file="$(mktemp)"
  cat >"$file" <<EOF
{
  "displayName": "$policy",
  "documentation": {
    "mimeType": "text/markdown",
    "content": "The hourly merge job counted more rows in price_observations than merge.PARTITION_AT. Partition the table by month (pruning then drops whole partitions), or shorten prices.KEEP_DAYS. The job label says whether it is prod's or staging's."
  },
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "merge logged partition-observations",
      "conditionMatchedLog": {
        "filter": "resource.type=\"cloud_run_job\" AND severity=WARNING AND jsonPayload.alert=\"partition-observations\"",
        "labelExtractors": {"job": "EXTRACT(resource.labels.job_name)"}
      }
    }
  ],
  "alertStrategy": {"notificationRateLimit": {"period": "86400s"}, "autoClose": "604800s"},
  "notificationChannels": ["$channel"]
}
EOF
  gcloud alpha monitoring policies create --policy-from-file "$file" "${G[@]}"
  rm -f "$file"
}

case "${1:-}" in
  apis | registry | accounts | sql | firestore | wif) "$1" ;;
  alerts) alerts "${2:-}" ;;
  database) database "${2:-}" ;;
  scheduler) scheduler "${2:-}" ;;
  job-runner) job_runner "${2:-}" ;;
  staging-auth) staging_auth ;;
  *)
    sed -n '2,22p' "$0"
    exit 1
    ;;
esac
