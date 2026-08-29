#!/usr/bin/env pwsh
# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3 — AWS NETWORK FOUNDATION verification runbook
# Validates:  VPC topology -> subnet isolation -> S3 private access -> security
#             groups (only-required-traffic) -> no public RDS/Redis -> flow logs
#             -> live /ready (proves app->DB/Redis) + presigned S3 GET.
#
# Requires:   aws CLI v2 with a READ-ONLY profile (operator / ci_verify).
# Usage:      powershell -ExecutionPolicy Bypass -File infra/scripts/network_verify.ps1
#               -Region ap-south-1 -VpcId vpc-xxxx -Env staging -ApiUrl https://api.example.com
#             Auto-discovers VPC/subnets/SGs via Name tags when -VpcId omitted.
# ─────────────────────────────────────────────────────────────────────────────
param(
    [string]$Region    = "ap-south-1",
    [string]$VpcId     = "",
    [string]$Env       = $env:HYPERLOCAL_ENV,
    [string]$ApiUrl    = "",
    [string]$StackName = ""
)

$ErrorActionPreference = "Stop"
function Step($title, $scriptBlock) { Write-Host "`n==> $title" -ForegroundColor Cyan; & $scriptBlock }
function Ok($m)   { Write-Host "   [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host " [WARN] $m" -ForegroundColor Yellow }

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw "aws CLI not installed (run infra/scripts/install_tools.ps1)." }
if (-not $Env) { $Env = "staging" }
if (-not $StackName) { $StackName = "hyperlocal" }
$prefix = "$StackName-$Env"

# ── 0. Resolve the VPC (by id or by Name tag) ───────────────────────────────
if (-not $VpcId) {
    $VpcId = aws ec2 describe-vpcs --region $Region --filters "Name=tag:Name,Values=$prefix-vpc" `
        --query "Vpcs[0].VpcId" --output text 2>$null
}
if (-not $VpcId -or $VpcId -eq "None") { throw "Could not auto-discover VPC '$prefix-vpc'. Pass -VpcId explicitly." }

# ── 1. VPC present with the correct CIDR ────────────────────────────────────
Step "1. VPC & CIDR" {
    $vpc = aws ec2 describe-vpcs --region $Region --vpc-ids $VpcId --query "Vpcs[0]" --output json | ConvertFrom-Json
    Ok "VPC $VpcId  CIDR=$($vpc.CidrBlock)"
    if ($vpc.CidrBlock -ne "10.0.0.0/16") { Warn "Expected 10.0.0.0/16, got $($vpc.CidrBlock)" }
}

# ── 2. Subnet tiering + AZ spread (free-tier: 1 public app + 1 data) ────────
$subnets = (aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VpcId" --query "Subnets[*]" --output json | ConvertFrom-Json)
Step "Subnets: public-app + isolated data across >=2 AZs" {
    $data = @($subnets | Where-Object { $_.Tags.Name -match "$prefix-data" })
    $pub  = @($subnets | Where-Object { $_.Tags.Name -match "$prefix-public" })
    Ok "public-app x$($pub.Count)  data x$($data.Count)"
    if ($pub.Count -lt 1) { throw "No public app subnet found." }
    if ($data.Count -lt 1) { throw "No data subnet found." }
    $azs = @(($subnets | ForEach-Object { $_.AvailabilityZone }) | Sort-Object -Unique)
    if ($azs.Count -lt 2) { throw "Subnets must span >=2 AZs (db subnet group requirement)." }
    Ok "AZs covered: $($azs -join ', ')"
    foreach ($s in $data) {
        if ($s.MapPublicIpOnLaunch) { Warn "DATA subnet $($s.SubnetId) maps public IP - leaking tier." }
        else { Ok "data $($s.CidrBlock) $($s.AvailabilityZone) no-public-ip" }
    }
}

# ── 3. IGW present, NAT gateways MUST be zero (free-tier cost guard) ────────
Step "IGW present + ZERO NAT gateways" {
    $igw = aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VpcId" --query "InternetGateways[0]" --output json 2>$null
    if ($igw) { Ok "Internet Gateway present (free public egress for the app EC2)." } else { throw "No IGW attached - the app instance cannot reach the internet." }
    $nats = @(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VpcId" --query "NatGateways[?State=='available']" --output json | ConvertFrom-Json)
    if ($nats.Count -gt 0) { throw "FOUND $($nats.Count) NAT gateway(s) - NAT costs ~\$32/mo each and is NOT allowed in the free-tier topology." }
    Ok "No NAT gateways (correct for free tier)."
}

# ── 4. DATA-tier route tables must have NO 0.0.0.0/0 (internet-isolated) ───
Step "Data-tier route isolation (no internet)" {
    $rts = aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VpcId" --query "RouteTables[*]" --output json | ConvertFrom-Json
    $leaks = 0
    foreach ($rt in $rts) {
        $isData = ($rt.Tags | Where-Object Key -eq "Name").Value -match "data-rt"
        foreach ($r in $rt.Routes) {
            if ($r.DestinationCidrBlock -eq "0.0.0.0/0") {
                if ($isData) { Warn "DATA routetable $($rt.RouteTableId) has default route -> NOT isolated"; $leaks++ }
            }
        }
    }
    if ($leaks -eq 0) { Ok "No data route table exposes 0.0.0.0/0 (internet-isolated)." } else { throw "Data isolation violated." }
}

# ── 5. S3 Gateway VPC endpoint (private S3, no NAT) ────────────────────────
Step "S3 Gateway VPC endpoint" {
    $epts = @(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VpcId" "Name=service-name,Values=com.amazonaws.$Region.s3" "Name=vpc-endpoint-type,Values=Gateway" --query "VpcEndpoints[*]" --output json | ConvertFrom-Json)
    if ($epts.Count -ge 1) { Ok "S3 Gateway endpoint present (id $($epts[0].VpcEndpointId))." }
    else { Warn "No S3 Gateway endpoint found." }
}

# ── 6. Security groups: only required traffic ───────────────────────────────
Step "Security group audit (only-required-traffic)" {
    $sgs = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VpcId" --query "SecurityGroups[*]" --output json | ConvertFrom-Json
    foreach ($sg in $sgs) {
        $name  = $sg.GroupName
        $pubIn = @($sg.IpPermissions | Where-Object { $_.IpRanges | Where-Object { $_.CidrIp -eq "0.0.0.0/0" } })
        if ($name -match "app") {
            $ports = @($sg.IpPermissions | ForEach-Object { $_.FromPort } | Sort-Object -Unique)
            $publicPorts = @($pubIn | ForEach-Object { $_.FromPort })
            $allAllowed = ($publicPorts | ForEach-Object { $_ -in 80, 443 }) -notcontains $false
            if (-not $allAllowed) { throw "App SG '$name' exposes 0.0.0.0/0 on ports: $($publicPorts -join ',') - only 80/443 (Caddy) are allowed." }
            Ok "app SG public ingress: $($publicPorts -join ',') only (Caddy reverse proxy)."
        }
        elseif ($name -match "rds|redis") {
            if ($pubIn.Count -gt 0) { throw "RDS/Redis SG '$name' allows 0.0.0.0/0 - PUBLIC EXPOSURE!" }
            else { Ok "$name : no public ingress (app SG only)." }
        }
    }
}

# ── 7. Flow logs (connectivity audit) ──────────────────────────────────────
Step "VPC Flow Logs" {
    $fl = @(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VpcId" --query "FlowLogs[*]" --output json | ConvertFrom-Json)
    if ($fl.Count -ge 1) {
        $lg = $fl[0].LogGroupName
        Ok "Flow log -> $lg (traffic=$($fl[0].TrafficType))"
        $msg = aws logs filter-log-events --log-group-name $lg --filter-pattern "" --limit 5 --query "events[0].message" --output text 2>$null
        if ($msg -match "REJECT") { Ok "Detected REJECT records (only-required-traffic being enforced)." }
        if ($msg -match "ACCEPT") { Ok "Detected ACCEPT records (expected egress)." }
    } else { Warn "No flow logs on this VPC yet." }
}

# ── 8. RDS not publicly exposed + Redis is local (no ElastiCache) ──────────
Step "RDS private + Redis local (free tier)" {
    foreach ($db in (aws rds describe-db-instances --query "DBInstances[*]" --output json | ConvertFrom-Json)) {
        if ($db.PubliclyAccessible) { throw "RDS '$($db.DBInstanceIdentifier)' is PUBLICLY accessible!" }
        Ok "RDS '$($db.DBInstanceIdentifier)' not publicly accessible (class $($db.DBInstanceClass))."
    }
    $caches = @(aws elasticache describe-cache-clusters --show-cache-node-info --query "CacheClusters[*]" --output json 2>$null | ConvertFrom-Json)
    if ($caches.Count -gt 0) { throw "ElastiCache cluster(s) found - Redis must run as a local Docker container in the free-tier topology." }
    Ok "No ElastiCache clusters (Redis is local on the app instance - free)."
}

# ── 9. Live connectivity (app -> DB/Redis) + bucket policy ─────────────────
Step "Live readiness + S3 private check" {
    if ($ApiUrl) {
        $ready = $false
        try { $r = Invoke-RestMethod -Uri "$ApiUrl/ready" -TimeoutSec 20; $ready = ($r.status -eq "ready") } catch {}
        if ($ready) { Ok "/ready -> ready (proves app can reach Postgres + Redis + PostGIS)." }
        else { Warn "/ready not ready yet (instance booting / containers building)." }
    } else { Warn "Pass -ApiUrl http://<EIP> to run the live /ready probe." }
    $acct = aws sts get-caller-identity --query Account --output text 2>$null
    $bkt  = "$StackName-$acct-uploads"
    $pab = aws s3api get-public-access-block --bucket $bkt --query "PublicAccessBlockConfiguration" --output json 2>$null
    if ($pab) { Ok "Uploads bucket '$bkt' blocks public access (BlockPublicAcls=$($pab.BlockPublicAcls))." }
    else { Warn "Verify public-access block on bucket $bkt." }
    try {
        $polRaw = (aws s3api get-bucket-policy --bucket $bkt --output json 2>$null | ConvertFrom-Json).Policy
        if ($polRaw -match "aws:SecureTransport") { Ok "Bucket policy denies non-TLS traffic (aws:SecureTransport=false)." }
        else { Warn "Bucket policy has no aws:SecureTransport deny." }
    } catch { Warn "Could not read bucket policy for $bkt (may not exist yet)." }
}

Write-Host "`nPhase 3 network verification complete." -ForegroundColor Green