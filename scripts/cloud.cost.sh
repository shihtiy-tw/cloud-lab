#!/usr/bin/env bash
#
# cloud.cost.sh - Analyse actual costs and estimate planned costs.
#
# Usage:
#   ./scripts/cloud.cost.sh --cloud aws --timeframe 30d
#   ./scripts/cloud.cost.sh --cloud aws --estimate --service compute/ecs
#   ./scripts/cloud.cost.sh --help
#
# See .opencode/command/cloud.cost.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

readonly VALID_BREAKDOWNS=(service tag region account)

CLOUD=""
TIMEFRAME="30d"
BREAKDOWN="service"
TAG_KEY="Environment"
ESTIMATE=false
PLAN_FILE=""
SERVICE=""
EXPORT=""
PROJECT=""
RESOURCE_GROUP=""
COMPARTMENT=""
TENANCY=""
BILLING_TABLE=""
START_DATE=""
END_DATE=""
TMP_DIR=""

show_help() {
  cat <<EOF
Usage: $(basename "$0") --cloud <provider> [--timeframe <period>] [OPTIONS]
       $(basename "$0") --cloud <provider> --estimate --service <path>
       $(basename "$0") --cloud <provider> --estimate --plan <plan-file>

Report actual cloud spend, or estimate the cost of a Terraform plan.

Required:
  --cloud <provider>     Cloud provider: ${VALID_CLOUDS[*]}
                         (falls back to CLOUD_PROVIDER in .cloud-context)

Actual-cost options:
  --timeframe <period>   7d | 30d | 90d | Nd | YYYY-MM-DD:YYYY-MM-DD (default: ${TIMEFRAME})
  --breakdown-by <dim>   ${VALID_BREAKDOWNS[*]} (default: ${BREAKDOWN})
  --tag-key <key>        Tag to group by when --breakdown-by tag (default: ${TAG_KEY})
  --export <file>        Write results to a .csv or .json file

Estimate options:
  --estimate             Estimate from Terraform rather than reading billing data
  --service <path>       Service path to estimate, e.g. compute/ecs
  --plan <file>          Terraform plan file (JSON, or binary with --service)

Provider-specific:
  GCP      --project <id>        --billing-table <project.dataset.table>
  Azure    --rg <resource-group>
  Oracle   --compartment <ocid>  --tenancy <ocid>

Options:
  --help                 Show this help message
  --version              Show version

Coverage note:
  AWS actual costs are read from Cost Explorer and rendered as a ranked table
  with percentages. GCP, Azure, and Oracle billing queries are issued through
  their own CLIs and their native output is passed through unchanged, because
  their response shapes vary by account configuration.

Prerequisites:
  Actual costs   the provider CLI, plus billing read permissions
                 GCP also needs a BigQuery billing export table
  Estimates      infracost (https://www.infracost.io/docs/)

Exit codes:
  0 success    1 error    2 invalid usage    3 missing dependency

Examples:
  $(basename "$0") --cloud aws --timeframe 30d --breakdown-by service
  $(basename "$0") --cloud aws --timeframe 2026-01-01:2026-02-01 --export costs.csv
  $(basename "$0") --cloud aws --estimate --service compute/ecs/infrastructure/cluster
  $(basename "$0") --cloud gcp --project my-project --billing-table my-project.billing.gcp_billing_export_v1
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cloud)
        CLOUD="${2:-}"
        shift 2
        ;;
      --timeframe)
        TIMEFRAME="${2:-}"
        shift 2
        ;;
      --breakdown-by)
        BREAKDOWN="${2:-}"
        shift 2
        ;;
      --tag-key)
        TAG_KEY="${2:-}"
        shift 2
        ;;
      --estimate)
        ESTIMATE=true
        shift
        ;;
      --plan)
        PLAN_FILE="${2:-}"
        shift 2
        ;;
      --service)
        SERVICE="${2:-}"
        shift 2
        ;;
      --export)
        EXPORT="${2:-}"
        shift 2
        ;;
      --project)
        PROJECT="${2:-}"
        shift 2
        ;;
      --rg | --resource-group)
        RESOURCE_GROUP="${2:-}"
        shift 2
        ;;
      --compartment)
        COMPARTMENT="${2:-}"
        shift 2
        ;;
      --tenancy)
        TENANCY="${2:-}"
        shift 2
        ;;
      --billing-table)
        BILLING_TABLE="${2:-}"
        shift 2
        ;;
      --help | -h)
        show_help
        exit "${EX_OK}"
        ;;
      --version)
        print_version
        exit "${EX_OK}"
        ;;
      *)
        unknown_option "$1" || exit $?
        ;;
    esac
  done
}

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}

# resolve_timeframe - set START_DATE and END_DATE from --timeframe
resolve_timeframe() {
  if [[ "${TIMEFRAME}" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}):([0-9]{4}-[0-9]{2}-[0-9]{2})$ ]]; then
    START_DATE="${BASH_REMATCH[1]}"
    END_DATE="${BASH_REMATCH[2]}"
  elif [[ "${TIMEFRAME}" =~ ^([0-9]+)d$ ]]; then
    local days="${BASH_REMATCH[1]}"
    if [[ "${days}" -lt 1 ]]; then
      log_error "--timeframe must cover at least one day"
      return "${EX_USAGE}"
    fi
    START_DATE="$(date -u -d "${days} days ago" '+%Y-%m-%d')"
    END_DATE="$(date -u '+%Y-%m-%d')"
  else
    log_error "invalid --timeframe '${TIMEFRAME}'"
    log_error "  expected Nd (e.g. 30d) or YYYY-MM-DD:YYYY-MM-DD"
    return "${EX_USAGE}"
  fi

  if [[ ! "${START_DATE}" < "${END_DATE}" ]]; then
    log_error "timeframe start (${START_DATE}) must be before end (${END_DATE})"
    return "${EX_USAGE}"
  fi
  return 0
}

# aws_group_by - the Cost Explorer group-by argument for --breakdown-by
aws_group_by() {
  case "${BREAKDOWN}" in
    service) printf 'Type=DIMENSION,Key=SERVICE\n' ;;
    region) printf 'Type=DIMENSION,Key=REGION\n' ;;
    account) printf 'Type=DIMENSION,Key=LINKED_ACCOUNT\n' ;;
    tag) printf 'Type=TAG,Key=%s\n' "${TAG_KEY}" ;;
    *) return 1 ;;
  esac
}

# print_table <tsv-file> <title> - ranked cost table with percentages
print_table() {
  local tsv="$1"
  local title="$2"

  printf '\n%s\n' "${title}"
  printf 'Period: %s to %s\n\n' "${START_DATE}" "${END_DATE}"

  if [[ ! -s "${tsv}" ]]; then
    printf 'No cost data returned for this period.\n'
    return 0
  fi

  # Sum duplicate labels (Cost Explorer returns one row per period per group),
  # then rank and add each label's share of the total.
  awk -F'\t' '
    { gsub(/\r/, ""); if ($1 == "") $1 = "(untagged)"; total[$1] += $2; grand += $2 }
    END {
      hdr = sprintf("%-40s | %14s | %10s", "Item", "Cost (USD)", "% of Total")
      print hdr
      n = length(hdr)
      bar = ""
      for (i = 0; i < n; i++) bar = bar "-"
      print bar
      cnt = 0
      for (k in total) { keys[++cnt] = k }
      for (i = 1; i < cnt; i++)
        for (j = i + 1; j <= cnt; j++)
          if (total[keys[j]] > total[keys[i]]) { t = keys[i]; keys[i] = keys[j]; keys[j] = t }
      for (i = 1; i <= cnt; i++) {
        k = keys[i]
        pct = (grand > 0) ? (total[k] * 100 / grand) : 0
        printf "%-40.40s | %14.2f | %9.1f%%\n", k, total[k], pct
      }
      print bar
      printf "%-40s | %14.2f | %9.1f%%\n", "TOTAL", grand, (grand > 0 ? 100 : 0)
    }
  ' "${tsv}"
  return 0
}

# aggregate_costs <tsv-file> - sum duplicate labels, ranked by cost descending
aggregate_costs() {
  awk -F'\t' '
    { gsub(/\r/, ""); if ($1 == "") $1 = "(untagged)"; total[$1] += $2 }
    END { for (k in total) printf "%s\t%.2f\n", k, total[k] }
  ' "$1" | sort -t"$(printf '\t')" -k2 -rn
}

# export_results <tsv-file>
export_results() {
  local tsv="$1"
  if [[ -z "${EXPORT}" ]]; then
    return 0
  fi

  # Aggregate once so CSV and JSON are byte-stable and ranked the same way as
  # the printed table.
  local agg="${TMP_DIR}/aggregate.tsv"
  aggregate_costs "${tsv}" >"${agg}"

  local total_rows
  total_rows="$(wc -l <"${agg}")"

  if [[ "${EXPORT}" == *.json ]]; then
    {
      printf '{\n'
      printf '  "cloud": "%s",\n' "${CLOUD}"
      printf '  "start_date": "%s",\n' "${START_DATE}"
      printf '  "end_date": "%s",\n' "${END_DATE}"
      printf '  "breakdown_by": "%s",\n' "${BREAKDOWN}"
      printf '  "currency": "USD",\n'
      printf '  "items": [\n'
      local n=0 item cost sep
      while IFS=$'\t' read -r item cost; do
        n=$((n + 1))
        sep=","
        if [[ "${n}" -eq "${total_rows}" ]]; then
          sep=""
        fi
        # Escape backslashes first, then quotes, so JSON stays well-formed.
        item="${item//\\/\\\\}"
        item="${item//\"/\\\"}"
        printf '    {"item": "%s", "cost": %s}%s\n' "${item}" "${cost}" "${sep}"
      done <"${agg}"
      printf '  ]\n'
      printf '}\n'
    } >"${EXPORT}"
  else
    {
      printf 'item,cost_usd\n'
      local item cost
      while IFS=$'\t' read -r item cost; do
        # Quote the label and double any embedded quotes, per RFC 4180.
        item="${item//\"/\"\"}"
        printf '"%s",%s\n' "${item}" "${cost}"
      done <"${agg}"
    } >"${EXPORT}"
  fi
  log_success "exported to ${EXPORT}"
  return 0
}

# cost_aws - Cost Explorer, normalised into a ranked table
cost_aws() {
  require_cmd aws "$(csp_cli_hint aws)" || return $?

  local group_by
  group_by="$(aws_group_by)"
  local tsv="${TMP_DIR}/aws-cost.tsv"

  log_info "querying Cost Explorer (${START_DATE} to ${END_DATE}, by ${BREAKDOWN})"
  local rc=0
  aws ce get-cost-and-usage \
    --time-period "Start=${START_DATE},End=${END_DATE}" \
    --granularity MONTHLY \
    --metrics UnblendedCost \
    --group-by "${group_by}" \
    --query 'ResultsByTime[].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' \
    --output text >"${tsv}" 2>"${TMP_DIR}/aws-cost.err" || rc=$?

  if [[ "${rc}" -ne 0 ]]; then
    log_error "aws ce get-cost-and-usage failed (exit ${rc})"
    if [[ -s "${TMP_DIR}/aws-cost.err" ]]; then
      while IFS= read -r line; do log_error "  ${line}"; done <"${TMP_DIR}/aws-cost.err"
    fi
    log_error "  Cost Explorer needs the ce:GetCostAndUsage permission and must be enabled on the account"
    return "${EX_ERROR}"
  fi

  print_table "${tsv}" "Cloud Cost Report - AWS (by ${BREAKDOWN})"
  export_results "${tsv}"
  return 0
}

# cost_gcp - BigQuery billing export
cost_gcp() {
  require_cmd bq "$(csp_cli_hint gcp)" || return $?

  local project="${PROJECT:-${CLOUDSDK_CORE_PROJECT:-}}"
  if [[ -z "${project}" ]]; then
    log_error "GCP cost queries need a project: pass --project or set it via cloud.switch.sh"
    return "${EX_USAGE}"
  fi

  local table="${BILLING_TABLE:-${GCP_BILLING_EXPORT_TABLE:-}}"
  if [[ -z "${table}" ]]; then
    log_error "GCP has no cost API equivalent to Cost Explorer; it needs a BigQuery billing export"
    log_error "  pass --billing-table <project.dataset.table> or set GCP_BILLING_EXPORT_TABLE"
    log_error "  setup: https://cloud.google.com/billing/docs/how-to/export-data-bigquery"
    return "${EX_USAGE}"
  fi

  local group_col
  case "${BREAKDOWN}" in
    service) group_col="service.description" ;;
    region) group_col="location.region" ;;
    account) group_col="project.id" ;;
    tag) group_col="project.id" ;;
    *) group_col="service.description" ;;
  esac
  if [[ "${BREAKDOWN}" == "tag" ]]; then
    log_warn "tag breakdown is not supported for the BigQuery export here; grouping by project instead"
  fi

  log_info "querying ${table} via bq (native output)"
  bq query --project_id="${project}" --use_legacy_sql=false --format=pretty \
    "SELECT ${group_col} AS item, ROUND(SUM(cost), 2) AS cost_usd
     FROM \`${table}\`
     WHERE DATE(usage_start_time) >= '${START_DATE}'
       AND DATE(usage_start_time) < '${END_DATE}'
     GROUP BY item
     ORDER BY cost_usd DESC"
  return $?
}

# cost_azure - Cost Management query
cost_azure() {
  require_cmd az "$(csp_cli_hint azure)" || return $?

  local subscription="${AZURE_SUBSCRIPTION_ID:-${ARM_SUBSCRIPTION_ID:-}}"
  if [[ -z "${subscription}" ]]; then
    log_error "Azure cost queries need a subscription id"
    log_error "  set one with: ./scripts/cloud.switch.sh --cloud azure --subscription <id>"
    return "${EX_USAGE}"
  fi

  local scope="/subscriptions/${subscription}"
  if [[ -n "${RESOURCE_GROUP}" ]]; then
    scope="${scope}/resourceGroups/${RESOURCE_GROUP}"
  fi

  local dimension
  case "${BREAKDOWN}" in
    service) dimension="ServiceName" ;;
    region) dimension="ResourceLocation" ;;
    account) dimension="SubscriptionName" ;;
    tag) dimension="ResourceGroupName" ;;
    *) dimension="ServiceName" ;;
  esac
  if [[ "${BREAKDOWN}" == "tag" ]]; then
    log_warn "tag breakdown needs a tag-scoped query; grouping by resource group instead"
  fi

  log_info "querying Cost Management for ${scope} (native output)"
  az costmanagement query \
    --scope "${scope}" \
    --type ActualCost \
    --timeframe Custom \
    --time-period "from=${START_DATE}T00:00:00Z" "to=${END_DATE}T00:00:00Z" \
    --dataset-granularity None \
    --dataset-grouping name="${dimension}" type=Dimension \
    --output table
  return $?
}

# cost_oracle - OCI Usage API
cost_oracle() {
  require_cmd oci "$(csp_cli_hint oracle)" || return $?

  local tenancy="${TENANCY:-${OCI_TENANCY:-${OCI_CLI_TENANCY:-}}}"
  if [[ -z "${tenancy}" ]]; then
    log_error "OCI cost queries need a tenancy OCID"
    log_error "  pass --tenancy <ocid> or export OCI_TENANCY"
    return "${EX_USAGE}"
  fi

  local group
  case "${BREAKDOWN}" in
    service) group='["service"]' ;;
    region) group='["region"]' ;;
    account) group='["compartmentName"]' ;;
    tag) group='["compartmentName"]' ;;
    *) group='["service"]' ;;
  esac
  if [[ "${BREAKDOWN}" == "tag" ]]; then
    log_warn "tag breakdown is not exposed by the Usage API here; grouping by compartment instead"
  fi

  log_info "querying the OCI Usage API (native output)"
  local -a cmd=(
    oci usage-api usage-summary request-summarized-usages
    --tenant-id "${tenancy}"
    --time-usage-started "${START_DATE}T00:00:00Z"
    --time-usage-ended "${END_DATE}T00:00:00Z"
    --granularity MONTHLY
    --query-type COST
    --group-by "${group}"
  )
  if [[ -n "${COMPARTMENT}" ]]; then
    cmd+=(--compartment-depth 6)
  fi
  "${cmd[@]}"
  return $?
}

# estimate_costs - infracost against a Terraform directory or plan JSON
estimate_costs() {
  require_cmd infracost "https://www.infracost.io/docs/#quick-start" || return $?

  local path=""

  if [[ -n "${PLAN_FILE}" ]]; then
    if [[ ! -f "${PLAN_FILE}" ]]; then
      log_error "plan file not found: ${PLAN_FILE}"
      return "${EX_USAGE}"
    fi
    # infracost reads plan JSON, not Terraform's binary plan format.
    if head -c 1 "${PLAN_FILE}" | grep -q '{'; then
      path="${PLAN_FILE}"
    else
      log_info "${PLAN_FILE} is a binary plan; converting with terraform show -json"
      require_cmd terraform "https://developer.hashicorp.com/terraform/downloads" || return $?
      if [[ -z "${SERVICE}" ]]; then
        log_error "converting a binary plan needs --service so the Terraform root is known"
        log_error "  either pass --service <path>, or generate JSON with: terraform show -json <plan> > plan.json"
        return "${EX_USAGE}"
      fi
      local svc_dir tf_dir
      svc_dir="$(require_service_dir "${CLOUD}" "${SERVICE}")" || return $?
      if ! tf_dir="$(resolve_tf_dir "${svc_dir}")"; then
        report_tf_candidates "${CLOUD}" "${SERVICE}" "${svc_dir}"
        return "${EX_USAGE}"
      fi
      path="${TMP_DIR}/plan.json"
      terraform -chdir="${tf_dir}" show -json "${PLAN_FILE}" >"${path}"
    fi
  else
    if [[ -z "${SERVICE}" ]]; then
      log_error "--estimate needs either --service <path> or --plan <file>"
      return "${EX_USAGE}"
    fi
    local svc_dir
    svc_dir="$(require_service_dir "${CLOUD}" "${SERVICE}")" || return $?
    local tf_dir
    if ! tf_dir="$(resolve_tf_dir "${svc_dir}")"; then
      report_tf_candidates "${CLOUD}" "${SERVICE}" "${svc_dir}"
      return "${EX_USAGE}"
    fi
    path="${tf_dir}"
  fi

  log_section "Cost estimate - ${CLOUD} ${SERVICE:-${PLAN_FILE}}"
  local -a cmd=(infracost breakdown --path "${path}")
  if [[ -n "${EXPORT}" ]]; then
    if [[ "${EXPORT}" == *.json ]]; then
      cmd+=(--format json --out-file "${EXPORT}")
    else
      cmd+=(--format table --out-file "${EXPORT}")
    fi
  fi
  log_info "${cmd[*]}"
  "${cmd[@]}"
  if [[ -n "${EXPORT}" ]]; then
    log_success "exported to ${EXPORT}"
  fi
  return 0
}

main() {
  parse_args "$@"

  local resolved
  resolved="$(resolve_cloud "${CLOUD}" || true)"
  CLOUD="${resolved}"
  validate_cloud "${CLOUD}" || exit $?

  if ! in_list "${BREAKDOWN}" "${VALID_BREAKDOWNS[@]}"; then
    die "${EX_USAGE}" "invalid --breakdown-by '${BREAKDOWN}' (expected one of: ${VALID_BREAKDOWNS[*]})"
  fi

  if context_load; then
    log_info "loaded provider context from ${CONTEXT_FILE#"${REPO_ROOT}"/}"
  fi

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT

  if [[ "${ESTIMATE}" == true ]]; then
    estimate_costs || exit $?
    exit "${EX_OK}"
  fi

  resolve_timeframe || exit $?

  case "${CLOUD}" in
    aws) cost_aws || exit $? ;;
    gcp) cost_gcp || exit $? ;;
    azure) cost_azure || exit $? ;;
    oracle) cost_oracle || exit $? ;;
    *) die "${EX_USAGE}" "no cost backend for '${CLOUD}'" ;;
  esac
}

main "$@"
