import subprocess, json, os, time

instance_id = 'i-065d808a03be03f5e'
region = 'ap-south-1'
PGPASSWORD = '4ywa_ZWGH_8ux69K0b_TQevN4%216E%25zWY'
DBHOST = 'hyperlocal-production-db.czuwyk426jbf.ap-south-1.rds.amazonaws.com'

commands = [
    'export DEBIAN_FRONTEND=noninteractive',
    'if ! command -v psql >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq postgresql-client >/tmp/psql_install.log 2>&1; fi',
    'echo PSQL_READY',
    'PGPASSWORD=' + PGPASSWORD + ' psql -h ' + DBHOST + ' -U hyperlocal -d hyperlocal -c "SELECT count(*) AS table_count FROM information_schema.tables WHERE table_schema=\'public\';" 2>&1',
    'echo DONE'
]

cmd = ['aws', 'ssm', 'send-command', '--instance-ids', instance_id,
       '--document-name', 'AWS-RunShellScript', '--comment', 'psql-and-check',
       '--parameters', json.dumps({'commands': commands}),
       '--region', region, '--timeout-seconds', '600']
r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
try:
    cid = json.loads(r.stdout)['Command']['CommandId']
    open('_cmdid.txt', 'w').write(cid)
    print('SENT ' + cid)
except Exception as ex:
    open('_err.txt', 'w').write(str(ex) + '\n' + r.stdout[:300] + '\n' + r.stderr[:300])
    print('ERR ' + str(ex))