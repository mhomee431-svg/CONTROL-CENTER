import * as cdk from 'aws-cdk-lib';
import { ControlCenterStack } from '../lib/control-center-stack';

const deploymentEnvironment = process.env.DEPLOYMENT_ENV;
const domainName = process.env.DOMAIN_NAME;
const certificateArn = process.env.CERTIFICATE_ARN;

if (deploymentEnvironment !== 'staging' && deploymentEnvironment !== 'production') {
  throw new Error('Set DEPLOYMENT_ENV to staging or production before synthesizing the stack.');
}
if (!domainName || !certificateArn) {
  throw new Error('Set DOMAIN_NAME and CERTIFICATE_ARN before synthesizing the stack.');
}

const app = new cdk.App();

new ControlCenterStack(app, `HyperlocalControlCenter-${deploymentEnvironment}`, {
  deploymentEnvironment,
  domainName,
  certificateArn,
  hostedZoneId: process.env.HOSTED_ZONE_ID,
  hostedZoneName: process.env.HOSTED_ZONE_NAME,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
