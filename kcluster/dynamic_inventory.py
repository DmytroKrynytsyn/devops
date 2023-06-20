#!/usr/bin/env python
import json
import boto3

def get_ec2_by_tag(tag_key, tag_value):
    ec2_client = boto3.client('ec2')

    response = ec2_client.describe_instances(
        Filters=[
            { 'Name': 'instance-state-name', 'Values': ['running'] },
            { 'Name': f'tag:{tag_key}', 'Values': [tag_value] }
        ]
    )

    instances = []
    reservations = response['Reservations']
    for reservation in reservations:
        instances.extend(reservation['Instances'])

    return instances

def get_load_balancer_public_dns(load_balancer_name):
    elbv2_client = boto3.client('elbv2')
    response = elbv2_client.describe_load_balancers()
    
    if 'LoadBalancers' in response:
        load_balancer = response['LoadBalancers'][0]
        if 'DNSName' in load_balancer:
            return load_balancer['DNSName']
    
    return None

inventory = {'workers': {'hosts': [],  'vars': { 'ansible_user': 'root','ansible_ssh_private_key_file': './cks.pem'}}, 
        'masters': {'hosts': [],  'vars': { 'ansible_user': 'root','ansible_ssh_private_key_file': './cks.pem', 'elb':'elbname'}}, 
        '_meta': { 'hostvars':{}}}

elb_dns = get_load_balancer_public_dns('kcluster')

for instance in get_ec2_by_tag('Purpose', 'kcluster'):
    publicIp = instance['PublicIpAddress']
    privateIp = instance['PrivateIpAddress']
    privateDns = instance['PrivateDnsName']
    hostRole = [tag for tag in instance['Tags'] if tag['Key'] == 'Role'][0]['Value']

    hostName = privateDns[:privateDns.index(".")]

    if hostRole == 'kcluster_master':
        inventory['masters']['hosts'].append(hostName)
        inventory['masters']['vars']['elb'] = elb_dns
    elif hostRole == 'kcluster_worker':
        inventory['workers']['hosts'].append(hostName)

    inventory['_meta']['hostvars'].update( { hostName:{'ansible_host': publicIp, 'private_ip': privateIp}})

print(json.dumps(inventory))



