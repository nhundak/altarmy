# Names shared by deploy/*.sh. Sourced, not run. Every gcloud call passes the project explicitly, so the
# caller's gcloud defaults (project, quota project) never matter.
PROJECT=alt-army-prod
PROJECT_NUMBER=516573536063
REGION=us-central1
GCLOUD_FLAGS=(--project "$PROJECT" --billing-project "$PROJECT" --quiet)

REPO=altarmy                                   # Artifact Registry (docker)
IMAGE_BASE="$REGION-docker.pkg.dev/$PROJECT/$REPO/altarmy"

SQL_INSTANCE=altarmy-pg                        # Cloud SQL Postgres 16, db-f1-micro
SQL_CONNECTION="$PROJECT:$REGION:$SQL_INSTANCE"

PROD_RUN_SA="altarmy-run@$PROJECT.iam.gserviceaccount.com"                # prod's service and jobs run as this
STAGING_RUN_SA="altarmy-staging-run@$PROJECT.iam.gserviceaccount.com"     # staging's
STAGING_AUTH_PROJECT=alt-army-staging # staging's Firebase Auth (Spark, no billing: only IAM grants go there)
SCHEDULER_SA="altarmy-scheduler@$PROJECT.iam.gserviceaccount.com" # Cloud Scheduler starts jobs as this
DEPLOY_SA="altarmy-deploy@$PROJECT.iam.gserviceaccount.com"       # CI (Workload Identity Federation)

WIF_POOL=github
WIF_PROVIDER=github-actions
GITHUB_REPO=ntower/altarmy-profit

# Per environment: prod | staging. Sets SERVICE, DB_NAME, DB_USER, SECRET, JOB_PREFIX, MAX_INSTANCES, RUN_SA
# (the runtime service account) and FIREBASE_ENV (the env file with its Firebase web config).
env_config() {
  case "$1" in
    prod)
      SERVICE=altarmy DB_NAME=altarmy DB_USER=altarmy SECRET=database-url JOB_PREFIX=altarmy MAX_INSTANCES=2
      RUN_SA="$PROD_RUN_SA" FIREBASE_ENV=hosted.env
      ;;
    staging)
      SERVICE=altarmy-staging DB_NAME=altarmy_staging DB_USER=altarmy_staging SECRET=database-url-staging
      JOB_PREFIX=altarmy-staging MAX_INSTANCES=1 RUN_SA="$STAGING_RUN_SA" FIREBASE_ENV=staging.env
      ;;
    *)
      echo "environment must be prod or staging, not '$1'" >&2
      return 1
      ;;
  esac
}

# The environment's Firebase web config (public) from $FIREBASE_ENV (after env_config), as Cloud Run env vars.
# Fails if a value is missing, so a deploy never starts a service that can't sign anyone in.
firebase_env() {
  local root vars
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  vars="$(grep -E '^FIREBASE_(PROJECT_ID|API_KEY|AUTH_DOMAIN)=.+' "$root/${FIREBASE_ENV:?run env_config first}" | tr -d '\r')"
  if [ "$(printf '%s\n' "$vars" | grep -c .)" -ne 3 ]; then
    echo "$FIREBASE_ENV needs FIREBASE_PROJECT_ID, FIREBASE_API_KEY and FIREBASE_AUTH_DOMAIN" >&2
    return 1
  fi
  printf '%s\n' "$vars" | paste -sd, -
}
