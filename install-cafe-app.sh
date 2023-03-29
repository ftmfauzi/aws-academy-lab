#!/bin/bash
sudo sed -i "2i date.timezone = \"America/New_York\" " /etc/php.ini
sudo service httpd start
ln -s /var/www/ /home/ec2-user/environment
sudo usermod -a -G apache ec2-user
sudo chown -R ec2-user:apache /var/www
sudo chmod 2775 /var/www
echo '<html><h1>Hello From Your Web Server!</h1></html>' > /var/www/html/index.html
find /var/www -type d -exec chmod 2775 {} \;
find /var/www -type f -exec chmod 0664 {} \;
echo '<?php phpinfo(); ?>' > /var/www/html/phpinfo.php
cd ~/environment
wget https://aws-tc-largeobjects.s3-us-west-2.amazonaws.com/ILT-TF-200-ACACAD-20-EN/mod4-challenge/setup.tar.gz
tar -zxvf setup.tar.gz
wget https://aws-tc-largeobjects.s3-us-west-2.amazonaws.com/ILT-TF-200-ACACAD-20-EN/mod4-challenge/cafe.tar.gz
tar -zxvf cafe.tar.gz
mv cafe /var/www/html/

#set the browser tab titles so that they indicate that this is the dev instance
sed -i 's|Caf&eacute;!|Caf\&eacute; DEV|' /var/www/html/cafe/index.php
sed -i 's|Caf&eacute; Menu|Caf\&eacute; Menu DEV|' /var/www/html/cafe/menu.php
sed -i 's|Caf&eacute; Order History|Caf\&eacute; Order History DEV|' /var/www/html/cafe/orderHistory.php

#get the region
region=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone|sed 's/.$//')

#get the cloud9 instance SG ID and open port 80
sgId=$(aws ec2 describe-instances --region $region --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[SecurityGroups]" --output text | grep cloud9 | awk '{print $1}')
aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 80 --cidr 0.0.0.0/0

#attach the CafeRole to the Cloud9 instance
instanceId=$(aws ec2 describe-instances --region $region --query "Reservations[*].Instances[*].{InstanceId:InstanceId,SecurityGroups:SecurityGroups[*].[GroupId]}" | grep -B 3 $sgId | grep InstanceId | cut -d '"' -f4)

aws ec2 associate-iam-instance-profile --iam-instance-profile Name=CafeRole --instance-id $instanceId --region $region

#get the rds endpoint
while [[ "$rdsEndpoint" == "" ]]
do
  sleep 15
  echo "checking if RDS endpoint is available. This may take a few minutes, please be patient."
  rdsEndpoint=$(aws rds describe-db-instances --query "DBInstances[*].Endpoint[].{Address:Address}" --region $region |grep Address|cut -d '"' -f4)
done

echo "rdsEndpoint="$rdsEndpoint
echo "now setting parameter store variables..."

#the set ssm params
aws ssm put-parameter --name "/cafe/showServerInfo" --type "String" --value "false" --description "Show Server Information Flag" --overwrite --region $region
aws ssm put-parameter --name "/cafe/timeZone" --type "String" --value "America/New_York" --description "Time Zone" --overwrite --region $region
aws ssm put-parameter --name "/cafe/currency" --type "String" --value '$' --description "Currency Symbol" --overwrite --region $region
aws ssm put-parameter --name "/cafe/dbUrl" --type "String" --value $rdsEndpoint --description "Database URL" --overwrite --region $region
aws ssm put-parameter --name "/cafe/dbName" --type "String" --value "cafe_db" --description "Database Name" --overwrite --region $region
#intentionally set this username to be incorrect so student will need to correct it.
aws ssm put-parameter --name "/cafe/dbUser" --type "String" --value "root" --description "Database User Name" --overwrite --region $region
aws ssm put-parameter --name "/cafe/dbPassword" --type "String" --value "Caf3DbPassw0rd!" --description "Database Password" --overwrite --region $region

#populate the database with orders
wget https://aws-tc-largeobjects.s3-us-west-2.amazonaws.com/ILT-TF-200-ACACAD-20-EN/mod5-challenge/CafeDbDump.sql
sleep 2
mysql -u admin -pCaf3DbPassw0rd! --host $rdsEndpoint < CafeDbDump.sql

echo "DONE."
