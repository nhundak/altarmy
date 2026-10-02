#!/usr/bin/env bash
# Deploy an image to an environment, in order:
#   1. define the Cloud Run jobs with the new image (migrate, merge, ingest-tbc, ingest-forever, prune);
#      `setup.sh scheduler ENV` schedules all but migrate
#   2. run the migrate job and wait: migrations run once per deploy, before any new instance starts
#   3. deploy the Cloud Run service (its instances never migrate)
#   4. build the front end and deploy it to Firebase Hosting (prod: the live site; staging: the
#      `staging` preview channel, whose /api rewrites to the staging service), and the Firestore rules
#      to the environment's Firebase project (price signals, firestore.rules)
#   5. run the ingest jobs and wait: they reload the game data when the new image's ingest code or
#      hand-maintained CSVs changed (`ingest.fingerprint`), and otherwise find it loaded and stop
#
#   deploy/deploy.sh prod|staging IMAGE
set -euo pipefail
cd "$(dirname "$0")/.."
source deploy/config.sh
ENV_NAME="${1:?prod or staging}"
IMAGE="${2:?image, e.g. from deploy/build.sh}"
env_config "$ENV_NAME"
FIREBASE_VARS="$(firebase_env)" # its own Firebase project: prod's from hosted.env, staging's from staging.env

COMMON=(--image "$IMAGE" --region "$REGION" --service-account "$RUN_SA"
  --set-cloudsql-instances "$SQL_CONNECTION" --set-secrets "DATABASE_URL=$SECRET:latest")

job() { # job NAME ARGS...: the CLI with ARGS, as a Cloud Run job
  local name="$1"
  shift
  local args
  args="$(IFS=,; echo "$*")"
  gcloud run jobs deploy "$name" "${COMMON[@]}" --command altarmy-profit --args="$args" \
    --memory 2Gi --cpu 1 --max-retries 1 --task-timeout 30m     --set-env-vars "$FIREBASE_VARS,DB_POOL_SIZE=1,DB_MAX_OVERFLOW=0" \
    "${GCLOUD_FLAGS[@]}"
}

echo "== jobs ($ENV_NAME)"
job "$JOB_PREFIX-migrate" migrate
job "$JOB_PREFIX-merge" merge
job "$JOB_PREFIX-ingest-tbc" --game-version tbc ingest --only-if-new --cache /tmp/cache
job "$JOB_PREFIX-ingest-forever" --game-version forever ingest --only-if-new --cache /tmp/cache
job "$JOB_PREFIX-prune" prune

echo "== migrate"
gcloud run jobs execute "$JOB_PREFIX-migrate" --region "$REGION" --wait "${GCLOUD_FLAGS[@]}"

echo "== service $SERVICE"
# the jobs the Admin page's Run now starts (launch.CloudRunJobs; setup.sh job-runner lets the service)
RUN_JOBS="CLOUD_RUN_LOCATION=projects/$PROJECT/locations/$REGION,JOB_PREFIX=$JOB_PREFIX"
gcloud run deploy "$SERVICE" "${COMMON[@]}" \
  --allow-unauthenticated --min-instances 0 --max-instances "$MAX_INSTANCES" --concurrency 40 \
  --cpu 1 --memory 1Gi --cpu-boost --timeout 300 \
  --set-env-vars "$FIREBASE_VARS,DB_POOL_SIZE=3,DB_MAX_OVERFLOW=2,$RUN_JOBS" \
  "${GCLOUD_FLAGS[@]}"

echo "== front end"
(cd frontend && npm run build)
FIREBASE=(npx --yes firebase-tools@14 --project "$PROJECT" --non-interactive)
if [ "$ENV_NAME" = prod ]; then
  "${FIREBASE[@]}" deploy --only hosting,firestore:rules
else
  "${FIREBASE[@]}" --config firebase.staging.json hosting:channel:deploy staging --expires 30d
  # staging's price signals live in its own Firebase project
  npx --yes firebase-tools@14 --project "$STAGING_AUTH_PROJECT" --non-interactive --config firebase.staging.json     deploy --only firestore:rules
fi

echo "== game data"
for v in forever tbc; do
  gcloud run jobs execute "$JOB_PREFIX-ingest-$v" --region "$REGION" --wait "${GCLOUD_FLAGS[@]}"
done
