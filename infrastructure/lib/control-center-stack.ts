import * as path from 'node:path';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53Targets from 'aws-cdk-lib/aws-route53-targets';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

interface ControlCenterStackProps extends cdk.StackProps {
  deploymentEnvironment: 'staging' | 'production';
  domainName: string;
  certificateArn: string;
  hostedZoneId?: string;
  hostedZoneName?: string;
}

export class ControlCenterStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ControlCenterStackProps) {
    super(scope, id, props);

    const isProduction = props.deploymentEnvironment === 'production';
    const repositoryRoot = path.resolve(__dirname, '..', '..');
    const origin = `https://${props.domainName}`;

    if (Boolean(props.hostedZoneId) !== Boolean(props.hostedZoneName)) {
      throw new Error('HOSTED_ZONE_ID and HOSTED_ZONE_NAME must be set together.');
    }
    if (
      props.hostedZoneName
      && props.domainName !== props.hostedZoneName
      && !props.domainName.endsWith(`.${props.hostedZoneName}`)
    ) {
      throw new Error('DOMAIN_NAME must be the hosted zone apex or a subdomain of HOSTED_ZONE_NAME.');
    }

    const vpc = new ec2.Vpc(this, 'Vpc', {
      maxAzs: 2,
      natGateways: isProduction ? 2 : 1,
      subnetConfiguration: [
        { name: 'Public', subnetType: ec2.SubnetType.PUBLIC, cidrMask: 24 },
        { name: 'Application', subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, cidrMask: 24 },
        { name: 'Database', subnetType: ec2.SubnetType.PRIVATE_ISOLATED, cidrMask: 24 },
      ],
    });

    const cluster = new ecs.Cluster(this, 'Cluster', {
      vpc,
      containerInsightsV2: ecs.ContainerInsights.ENABLED,
    });

    const databaseCredentials = rds.Credentials.fromGeneratedSecret('hyperlocal_admin');
    const database = new rds.DatabaseInstance(this, 'Database', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16_4,
      }),
      credentials: databaseCredentials,
      databaseName: 'hyperlocal',
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T4G,
        isProduction ? ec2.InstanceSize.SMALL : ec2.InstanceSize.MICRO,
      ),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      publiclyAccessible: false,
      multiAz: isProduction,
      allocatedStorage: 20,
      maxAllocatedStorage: 100,
      storageType: rds.StorageType.GP3,
      backupRetention: cdk.Duration.days(7),
      deletionProtection: true,
      storageEncrypted: true,
      cloudwatchLogsExports: ['postgresql'],
      cloudwatchLogsRetention: isProduction
        ? logs.RetentionDays.ONE_MONTH
        : logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    if (!database.secret) {
      throw new Error('RDS did not provide the expected generated credential secret.');
    }

    const apiSecret = new secretsmanager.Secret(this, 'ApiSigningKey', {
      description: `Hyperlocal ${props.deploymentEnvironment} API signing key`,
      generateSecretString: {
        passwordLength: 64,
        excludePunctuation: true,
      },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'LoadBalancer', {
      vpc,
      internetFacing: true,
      dropInvalidHeaderFields: true,
      deletionProtection: isProduction,
      idleTimeout: cdk.Duration.minutes(5),
    });

    const certificate = acm.Certificate.fromCertificateArn(
      this,
      'Certificate',
      props.certificateArn,
    );
    const httpsListener = loadBalancer.addListener('HttpsListener', {
      port: 443,
      certificates: [certificate],
      open: true,
    });

    loadBalancer.addListener('HttpListener', {
      port: 80,
      open: true,
      defaultAction: elbv2.ListenerAction.redirect({
        protocol: 'HTTPS',
        port: '443',
        permanent: true,
      }),
    });

    const apiSecurityGroup = new ec2.SecurityGroup(this, 'ApiSecurityGroup', {
      vpc,
      allowAllOutbound: true,
    });
    const webSecurityGroup = new ec2.SecurityGroup(this, 'WebSecurityGroup', {
      vpc,
      allowAllOutbound: true,
    });
    const loadBalancerSecurityGroup = loadBalancer.connections.securityGroups[0];
    apiSecurityGroup.addIngressRule(loadBalancerSecurityGroup, ec2.Port.tcp(8000));
    webSecurityGroup.addIngressRule(loadBalancerSecurityGroup, ec2.Port.tcp(3000));
    database.connections.allowDefaultPortFrom(apiSecurityGroup);

    const apiTask = new ecs.FargateTaskDefinition(this, 'ApiTask', {
      cpu: 512,
      memoryLimitMiB: 1024,
    });
    const apiLogs = new logs.LogGroup(this, 'ApiLogs', {
      retention: isProduction ? logs.RetentionDays.ONE_MONTH : logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    const apiContainer = apiTask.addContainer('Api', {
      image: ecs.ContainerImage.fromAsset(path.resolve(repositoryRoot, 'backend')),
      logging: ecs.LogDrivers.awsLogs({ logGroup: apiLogs, streamPrefix: 'api' }),
      environment: {
        ENVIRONMENT: props.deploymentEnvironment,
        COOKIE_SECURE: 'true',
        DB_HOST: database.dbInstanceEndpointAddress,
        DB_PORT: database.dbInstanceEndpointPort,
        DB_NAME: 'hyperlocal',
        CORS_ORIGINS: JSON.stringify([origin]),
      },
      secrets: {
        SECRET_KEY: ecs.Secret.fromSecretsManager(apiSecret),
        DB_USER: ecs.Secret.fromSecretsManager(database.secret, 'username'),
        DB_PASSWORD: ecs.Secret.fromSecretsManager(database.secret, 'password'),
      },
      healthCheck: {
        command: ['CMD-SHELL', 'python -c "from urllib.request import urlopen; urlopen(\'http://127.0.0.1:8000/health\')"'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });
    apiContainer.addPortMappings({ containerPort: 8000 });

    const webTask = new ecs.FargateTaskDefinition(this, 'WebTask', {
      cpu: 512,
      memoryLimitMiB: 1024,
    });
    const webLogs = new logs.LogGroup(this, 'WebLogs', {
      retention: isProduction ? logs.RetentionDays.ONE_MONTH : logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    const webContainer = webTask.addContainer('Web', {
      image: ecs.ContainerImage.fromAsset(repositoryRoot, { file: 'Dockerfile' }),
      logging: ecs.LogDrivers.awsLogs({ logGroup: webLogs, streamPrefix: 'web' }),
      environment: {
        NODE_ENV: 'production',
        PORT: '3000',
        HOSTNAME: '0.0.0.0',
      },
      healthCheck: {
        command: ['CMD-SHELL', 'node -e "fetch(\'http://127.0.0.1:3000/login\').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });
    webContainer.addPortMappings({ containerPort: 3000 });

    const apiService = new ecs.FargateService(this, 'ApiService', {
      cluster,
      taskDefinition: apiTask,
      desiredCount: isProduction ? 2 : 1,
      assignPublicIp: false,
      securityGroups: [apiSecurityGroup],
      circuitBreaker: { enable: true, rollback: true },
      minHealthyPercent: isProduction ? 50 : 0,
      maxHealthyPercent: 200,
    });
    const webService = new ecs.FargateService(this, 'WebService', {
      cluster,
      taskDefinition: webTask,
      desiredCount: isProduction ? 2 : 1,
      assignPublicIp: false,
      securityGroups: [webSecurityGroup],
      circuitBreaker: { enable: true, rollback: true },
      minHealthyPercent: isProduction ? 50 : 0,
      maxHealthyPercent: 200,
    });

    httpsListener.addTargets('ApiTargets', {
      port: 8000,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [apiService],
      priority: 10,
      conditions: [elbv2.ListenerCondition.pathPatterns(['/api/v1/*', '/health'])],
      healthCheck: {
        path: '/health',
        healthyHttpCodes: '200',
      },
    });
    httpsListener.addTargets('WebTargets', {
      port: 3000,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [webService],
      healthCheck: {
        path: '/login',
        healthyHttpCodes: '200-399',
      },
    });

    if (props.hostedZoneId && props.hostedZoneName) {
      const zone = route53.HostedZone.fromHostedZoneAttributes(this, 'HostedZone', {
        hostedZoneId: props.hostedZoneId,
        zoneName: props.hostedZoneName,
      });
      new route53.ARecord(this, 'ApplicationRecord', {
        zone,
        recordName: props.domainName === props.hostedZoneName
          ? undefined
          : props.domainName.slice(0, -(props.hostedZoneName.length + 1)),
        target: route53.RecordTarget.fromAlias(
          new route53Targets.LoadBalancerTarget(loadBalancer),
        ),
      });
    }

    new cdk.CfnOutput(this, 'ApplicationUrl', {
      value: origin,
    });
    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      value: loadBalancer.loadBalancerDnsName,
    });
    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: database.dbInstanceEndpointAddress,
    });
  }
}
