#!/usr/bin/env bash
# Publishes pipeline health to CloudWatch (namespace ShipGuard/Pipeline).
#   scripts/pipeline_metric.sh 0   -> build succeeded
#   scripts/pipeline_metric.sh 1   -> build failed (a gate or the deploy broke)
# Uses the Jenkins instance role (cloudwatch:PutMetricData comes from CloudWatchAgentServerPolicy).
# Never fails the build itself: monitoring must not change the pipeline result.
set -uo pipefail
failed="${1:-1}"
region="${AWS_REGION:-}"
if [ -z "$region" ]; then
  echo "AWS_REGION not set (Init stage did not run); skipping pipeline metric"
  exit 0
fi
duration=$(( ($(date +%s%3N) - ${BUILD_START_MS:-$(date +%s%3N)}) / 1000 ))
aws cloudwatch put-metric-data --region "$region" --namespace "ShipGuard/Pipeline" --metric-data \
  "MetricName=BuildFailed,Value=${failed},Unit=Count" \
  "MetricName=BuildSucceeded,Value=$((1 - failed)),Unit=Count" \
  "MetricName=BuildDuration,Value=${duration},Unit=Seconds" \
  && echo "Pipeline metric sent (failed=${failed}, duration=${duration}s)" \
  || echo "Could not send pipeline metric (ignored)"
exit 0
