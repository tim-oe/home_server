#!/usr/bin/env bash
# Create a private S3 bucket and, optionally, tie it to one existing IAM user.
#
# The account owns the bucket. Passing a user ARN writes two policies that
# name that user:
#   - a customer managed IAM policy, attached to the user, granting object use
#   - a bucket policy that allows the same use and denies every other principal
#
# The deny exempts the user, the principal running this script, and the account
# root. Root is the break-glass path: an explicit deny would otherwise lock out
# every other admin, including whoever needs to change this policy later.
# Re-running replaces the exemption list, so a different caller takes the
# previous caller's place. The user is not granted bucket administration.
#
# The bucket is created in the account regional namespace, so the name only has
# to be unique for this account in this region. CreateBucket still requires the
# full name: <prefix>-<account id>-<region>-an. The BUCKET argument is that
# prefix; a name that already ends with the suffix is used unchanged.
#
# Transfer Acceleration is enabled on every run so a client can use the
# accelerate endpoint. A bucket name that contains a dot cannot use acceleration.
#
# Usage: s3-bucket.sh [--region REGION] BUCKET [USER_ARN]
# Credentials come from the AWS CLI chain (env, AWS_PROFILE, shared config).
set -euo pipefail

usage() {
  echo "Usage: s3-bucket.sh [--region REGION] BUCKET [USER_ARN]" >&2
  exit 2
}

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}

trace() { printf 'trace: %s\n' "$*"; }

# Keep stdout and stderr apart. AWS CLI writes the error code to stderr and,
# on success, the result JSON to stdout.
capture() {
  local out err
  out=$(mktemp)
  err=$(mktemp)
  set +e
  "$@" >"$out" 2>"$err"
  RUN_RC=$?
  set -e
  RUN_OUT=$(<"$out")
  RUN_ERR=$(<"$err")
  rm -f "$out" "$err"
}

trace_block() {
  local label=$1 text=$2
  if [ -z "$text" ]; then
    trace "$label: <empty>"
  else
    printf 'trace: %s:\n%s\n' "$label" "$text"
  fi
}

region_source=environment
region=${AWS_REGION:-${AWS_DEFAULT_REGION:-}}
while [ $# -gt 0 ]; do
  case "$1" in
    --region)
      [ $# -ge 2 ] || usage
      region=$2
      region_source=--region
      shift 2
      ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) break ;;
  esac
done

bucket=${1:-}
user_arn=${2:-}
[ $# -le 2 ] || usage
[ -n "$bucket" ] || usage
[[ $bucket =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || {
  echo "bucket name must be 3-63 chars: lowercase letters, digits, dots, hyphens" >&2
  exit 2
}
if [ -n "$user_arn" ]; then
  [[ $user_arn =~ ^arn:aws:iam::[0-9]{12}:user/.+ ]] || {
    echo "user arn must look like arn:aws:iam::123456789012:user/name" >&2
    exit 2
  }
fi

need aws
need jq

configured_region=$(aws configure get region || true)
if [ -z "$region" ]; then
  region=$configured_region
  region_source="aws configure get region"
fi
[ -n "$region" ] || { echo "no region: pass --region or set AWS_REGION" >&2; exit 1; }
env_aws_region=${AWS_REGION-<unset>}
env_aws_default_region=${AWS_DEFAULT_REGION-<unset>}
export AWS_REGION=$region AWS_DEFAULT_REGION=$region

trace "aws cli: $(aws --version 2>&1)"
trace "profile: ${AWS_PROFILE:-<unset, CLI default>}"
trace "env AWS_REGION=$env_aws_region AWS_DEFAULT_REGION=$env_aws_default_region"
trace "aws configure get region: ${configured_region:-<empty>}"
trace "using region: $region (from $region_source)"
trace "bucket prefix: $bucket"
trace "user arn: ${user_arn:-<none>}"

capture aws sts get-caller-identity --output json
trace "sts get-caller-identity exit $RUN_RC"
trace_block "sts stdout" "$RUN_OUT"
trace_block "sts stderr" "$RUN_ERR"
account=""
caller_arn=""
if [ "$RUN_RC" -eq 0 ]; then
  account=$(jq -r '.Account' <<<"$RUN_OUT")
  caller_arn=$(jq -r '.Arn' <<<"$RUN_OUT")
fi
[ -n "$account" ] || { echo "sts get-caller-identity failed; cannot build the account-regional bucket name" >&2; exit 1; }

# CreateBucket does not add the suffix itself. The console does; the API does not.
bucket_prefix=$bucket
suffix="-${account}-${region}-an"
if [[ $bucket_prefix == *"$suffix" ]]; then
  bucket=$bucket_prefix
else
  bucket="${bucket_prefix}${suffix}"
fi
trace "account-regional name: $bucket"
[ "${#bucket}" -le 63 ] || {
  echo "account-regional name $bucket is ${#bucket} characters; the limit is 63. Shorten the prefix." >&2
  exit 2
}

in_account=unknown
capture aws s3api list-buckets --query "Buckets[?Name=='$bucket'].Name" --output text
trace "list-buckets exit $RUN_RC"
trace_block "list-buckets stdout" "$RUN_OUT"
trace_block "list-buckets stderr" "$RUN_ERR"
if [ "$RUN_RC" -eq 0 ]; then
  if [ "$RUN_OUT" = "$bucket" ]; then
    in_account=yes
  else
    in_account=no
  fi
fi
trace "bucket in this account: $in_account"

# us-east-1 rejects LocationConstraint; every other region requires it.
# account-regional reserves the name for this account, so a global collision
# on the prefix no longer rejects the create.
if [ "$region" = "us-east-1" ]; then
  trace "create-bucket: aws s3api create-bucket --bucket $bucket --bucket-namespace account-regional --region $region"
  trace "create-bucket: LocationConstraint omitted (us-east-1)"
  capture aws s3api create-bucket --bucket "$bucket" --bucket-namespace account-regional --region "$region"
else
  trace "create-bucket: aws s3api create-bucket --bucket $bucket --bucket-namespace account-regional --region $region --create-bucket-configuration LocationConstraint=$region"
  capture aws s3api create-bucket --bucket "$bucket" --region "$region" \
    --bucket-namespace account-regional \
    --create-bucket-configuration "LocationConstraint=$region"
fi
trace "create-bucket exit $RUN_RC"
trace_block "create-bucket stdout" "$RUN_OUT"
trace_block "create-bucket stderr" "$RUN_ERR"
create_msg="$RUN_ERR"$'\n'"$RUN_OUT"
if [ "$RUN_RC" -eq 0 ]; then
  echo "created bucket: $bucket"
elif grep -q 'BucketAlreadyOwnedByYou' <<<"$create_msg"; then
  echo "bucket exists: $bucket"
elif grep -q 'BucketAlreadyExists' <<<"$create_msg"; then
  trace "CreateBucket returned BucketAlreadyExists; probing get-bucket-location"
  capture aws s3api get-bucket-location --bucket "$bucket" --region "$region"
  trace "get-bucket-location exit $RUN_RC"
  trace_block "get-bucket-location stdout" "$RUN_OUT"
  trace_block "get-bucket-location stderr" "$RUN_ERR"
  echo "create-bucket rejected $bucket (BucketAlreadyExists)." >&2
  echo "bucket in this account: $in_account. caller: ${caller_arn:-<unknown>} account: ${account:-<unknown>}" >&2
  exit 1
else
  echo "cannot create bucket $bucket" >&2
  exit 1
fi

trace "put-public-access-block"
aws s3api put-public-access-block --bucket "$bucket" --region "$region" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
trace "put-bucket-ownership-controls"
aws s3api put-bucket-ownership-controls --bucket "$bucket" --region "$region" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
echo "blocked public access: $bucket"

trace "put-bucket-accelerate-configuration"
aws s3api put-bucket-accelerate-configuration --bucket "$bucket" --region "$region" \
  --accelerate-configuration Status=Enabled
echo "transfer acceleration enabled: $bucket"
echo "bucket name: $bucket"

[ -n "$user_arn" ] || exit 0
[ -n "$account" ] || { echo "sts get-caller-identity failed; cannot attach a policy" >&2; exit 1; }
user_account=${user_arn#arn:aws:iam::}
user_account=${user_account%%:*}
[ "$user_account" = "$account" ] || {
  echo "user is in account $user_account; caller is in $account" >&2
  exit 1
}

# Assumed-role sessions report an sts ARN. Bucket-policy conditions see the role ARN.
caller_principal=$caller_arn
if [[ $caller_arn =~ ^arn:aws:sts::([0-9]+):assumed-role/([^/]+)/ ]]; then
  caller_principal="arn:aws:iam::${BASH_REMATCH[1]}:role/${BASH_REMATCH[2]}"
fi

user_name=${user_arn##*/}
trace "iam user name: $user_name"
trace "caller principal for bucket policy: $caller_principal"
aws iam get-user --user-name "$user_name" >/dev/null

policy_name="s3-${bucket}-access"
policy_arn="arn:aws:iam::${account}:policy/${policy_name}"
bucket_arn="arn:aws:s3:::${bucket}"
object_arn="arn:aws:s3:::${bucket}/*"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Object use only. No bucket policy, ACL, or delete-bucket rights.
jq -nc --arg bucket "$bucket_arn" --arg objects "$object_arn" '{
  Version: "2012-10-17",
  Statement: [
    {
      Sid: "ListBucket",
      Effect: "Allow",
      Action: ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"],
      Resource: $bucket
    },
    {
      Sid: "ObjectAccess",
      Effect: "Allow",
      Action: [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"
      ],
      Resource: $objects
    }
  ]
}' >"$tmp/identity.json"

exempt=$(jq -nc --arg user "$user_arn" --arg caller "$caller_principal" \
  --arg root "arn:aws:iam::${account}:root" '[$user, $caller, $root] | unique')
jq -nc --arg user "$user_arn" --arg bucket "$bucket_arn" --arg objects "$object_arn" \
  --argjson exempt "$exempt" '{
  Version: "2012-10-17",
  Statement: [
    {
      Sid: "AllowUser",
      Effect: "Allow",
      Principal: {AWS: $user},
      Action: [
        "s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads",
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"
      ],
      Resource: [$bucket, $objects]
    },
    {
      Sid: "DenyEveryoneElse",
      Effect: "Deny",
      Principal: "*",
      Action: "s3:*",
      Resource: [$bucket, $objects],
      Condition: {StringNotEquals: {"aws:PrincipalArn": $exempt}}
    }
  ]
}' >"$tmp/bucket.json"

trace "iam policy: $policy_arn"
if aws iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
  version_count=$(aws iam list-policy-versions --policy-arn "$policy_arn" \
    --query 'length(Versions)' --output text)
  if [ "$version_count" -ge 5 ]; then
    oldest=$(aws iam list-policy-versions --policy-arn "$policy_arn" \
      --query 'sort_by(Versions[?IsDefaultVersion==`false`], &CreateDate)[0].VersionId' \
      --output text)
    aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$oldest"
  fi
  aws iam create-policy-version --policy-arn "$policy_arn" \
    --policy-document "file://${tmp}/identity.json" --set-as-default >/dev/null
  echo "updated policy: $policy_arn"
else
  aws iam create-policy --policy-name "$policy_name" \
    --description "Object access to s3://${bucket}" \
    --policy-document "file://${tmp}/identity.json" >/dev/null
  echo "created policy: $policy_arn"
fi

attached=$(aws iam list-attached-user-policies --user-name "$user_name" \
  --query "AttachedPolicies[?PolicyArn=='${policy_arn}'].PolicyArn | [0]" --output text)
if [ "$attached" = "$policy_arn" ]; then
  echo "policy already attached to $user_name"
else
  aws iam attach-user-policy --user-name "$user_name" --policy-arn "$policy_arn"
  echo "attached policy to $user_name"
fi

trace "put-bucket-policy"
aws s3api put-bucket-policy --bucket "$bucket" --region "$region" \
  --policy "file://${tmp}/bucket.json"
echo "bucket policy linked to $user_arn"
echo "exempt from deny: $(jq -r 'join(", ")' <<<"$exempt")"
echo "bucket name: $bucket"
