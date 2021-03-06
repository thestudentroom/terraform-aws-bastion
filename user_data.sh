#!/bin/bash -x
yum -y update --security


# Create a new folder for the log files
mkdir /var/log/bastion

# Allow ec2-user only to access this folder and its content
chown ec2-user:ec2-user /var/log/bastion
chmod -R 770 /var/log/bastion
setfacl -Rdm other:0 /var/log/bastion

mkdir /usr/bin/bastion

yum install -y make glibc-devel gcc patch openssl-devel

cd /home/ec2-user && wget https://dl.duosecurity.com/duo_unix-1.10.5.tar.gz
tar zxf /home/ec2-user/duo_unix-1.10.5.tar.gz
cd /home/ec2-user/duo_unix-1.10.5/ && ./configure --prefix=/usr && make && sudo make install

cat > /etc/duo/login_duo.conf << 'EOF'
[duo]
ikey = ${duo_ikey}
skey = ${duo_skey}
host = ${duo_host_api}
groups = bastion
motd = yes
EOF

/usr/sbin/groupadd bastion

/usr/sbin/update-motd --disable

cat > /etc/motd << 'EOF'
######################################################################################
# ${company_name} Bastion Host #
# This is a private system that that is controled by the ${company_name} Platform Team. #
# Access to sudo is prohibited due to the fact it is NOT needed, contact the Platform Team if you have any questions. #
# Access and commands are logged as well as MFA via Duo active for security reasons. #
# Disconnect IMMEDIATELY if you are not an authorized user! #
######################################################################################
EOF

# Make OpenSSH execute a custom script on logins
echo -e "\\nForceCommand /usr/sbin/login_duo" >> /etc/ssh/sshd_config

# Block some SSH features that bastion host users could use to circumvent the solution
awk '!/AllowTcpForwarding/' /etc/ssh/sshd_config > temp && mv temp /etc/ssh/sshd_config
awk '!/PermitTunnel/' /etc/ssh/sshd_config > temp && mv temp /etc/ssh/sshd_config
awk '!/X11Forwarding/' /etc/ssh/sshd_config > temp && mv temp /etc/ssh/sshd_config
echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config
echo "PermitTunnel yes" >> /etc/ssh/sshd_config
echo "X11Forwarding no" >> /etc/ssh/sshd_config
echo 'ClientAliveInterval 60' >> /etc/ssh/sshd_config


# 3. Prevent bastion host users from viewing processes owned by other users, because the log
#    file name is one of the "script" execution parameters.
mount -o remount,rw,hidepid=2 /proc
awk '!/proc/' /etc/fstab > temp && mv temp /etc/fstab
echo "proc /proc proc defaults,hidepid=2 0 0" >> /etc/fstab

# Restart the SSH service to apply /etc/ssh/sshd_config modifications.
service sshd restart

cat > /usr/bin/bastion/assign_eip << 'EOF'
#!/usr/bin/env bash

INSTANCEID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
PUBLICIP=`aws --region eu-west-1 ec2 describe-addresses --filter "Name=tag:Bastion,Values=1" | grep PublicIp | awk '{print $2}' | tr -d '",' | head -n1`

echo $INSTANCEID
echo $PUBLICIP

aws --region eu-west-1 ec2 associate-address --instance-id $INSTANCEID --public-ip $PUBLICIP
EOF

chmod 700 /usr/bin/bastion/assign_eip

/usr/bin/bastion/assign_eip >> /var/log/bastion/assign_eip.txt

############################
## EXPORT LOG FILES TO S3 ##
############################

cat > /usr/bin/bastion/sync_s3 << 'EOF'
#!/usr/bin/env bash
# Copy log files to S3 with server-side encryption enabled.
# Then, if successful, delete log files that are older than a day.
LOG_DIR="/var/log/bastion/"
aws s3 cp $LOG_DIR s3://${bucket_name}/logs/ --sse --region ${aws_region} --recursive && find $LOG_DIR* -mtime +1 -exec rm {} \;
EOF

chmod 700 /usr/bin/bastion/sync_s3

#######################################
## SYNCHRONIZE USERS AND PUBLIC KEYS ##
#######################################

# Bastion host users should log in to the bastion host with their personal SSH key pair.
# The public keys are stored on S3 with the following naming convention: "username.pub".
# This script retrieves the public keys, creates or deletes local user accounts as needed,
# and copies the public key to /home/username/.ssh/authorized_keys

cat > /usr/bin/bastion/sync_users << 'EOF'
#!/usr/bin/env bash
# The file will log user changes
LOG_FILE="/var/log/bastion/users_changelog.txt"

# The function returns the user name from the public key file name.
# Example: public-keys/sshuser.pub => sshuser

get_user_name () {
  echo "$1" | sed -e "s/.*\///g" | sed -e "s/\.pub//g"
}

# For each public key available in the S3 bucket

aws s3api list-objects --bucket ${bucket_name} --prefix public-keys/ --region ${aws_region} --output text --query 'Contents[?Size>`0`].Key' | sed -e "s/\t/\n/" | sed -e "s/\t/\n/" > ~/keys_retrieved_from_s3
while read line; do
  USER_NAME="`get_user_name "$line"`"
  # Make sure the user name is alphanumeric
  if [[ "$USER_NAME" =~ ^[a-z][-a-z0-9]*$ ]]; then
    # Create a user account if it does not already exist
    cut -d: -f1 /etc/passwd | grep -qx $USER_NAME
    if [ $? -eq 1 ]; then
      /usr/sbin/adduser $USER_NAME && \
      mkdir -m 700 /home/$USER_NAME/.ssh && \
      chown $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh && \
      echo "$line" >> ~/keys_installed && \
      echo "`date --date="today" "+%Y-%m-%d %H-%M-%S"`: Creating user account for $USER_NAME ($line)" >> $LOG_FILE
    fi
    # Copy the public key from S3, if an user account was created from this key
    if [ -f ~/keys_installed ]; then
      grep -qx "$line" ~/keys_installed
      if [ $? -eq 0 ]; then
        aws s3 cp s3://${bucket_name}/$line /home/$USER_NAME/.ssh/authorized_keys --region ${aws_region}
        chmod 600 /home/$USER_NAME/.ssh/authorized_keys
        chown $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh/authorized_keys
        aws s3 cp s3://${bucket_name}/private-keys/ /home/$USER_NAME/. --recursive --region ${aws_region}
        NEW_MD5_PACKER="`md5sum /home/$USER_NAME/packer.key | awk '{print $1}'`"
        NEW_MD5_ACCESS="`md5sum /home/$USER_NAME/production_access.key | awk '{print $1}'`"
        OLD_MD5_PACKER="`md5sum /home/$USER_NAME/.ssh/packer.key | awk '{print $1}'`"
        OLD_MD5_ACCESS="`md5sum /home/$USER_NAME/.ssh/production_access.key | awk '{print $1}'`"
        if ! cmp --silent "$MD5_PACKER" "$OLD_MD5_PACKER"; then
          /bin/rm /home/$USER_NAME/.ssh/packer.key
          /bin/mv /home/$USER_NAME/packer.key /home/$USER_NAME/.ssh/packer.key
        else
          echo "Packer key NOT updated" >> /var/log/bastion/packer_key_update.log
        fi
        if ! cmp --silent "$MD5_ACCESS" "$OLD_MD5_ACCESS"; then
          /bin/rm /home/$USER_NAME/.ssh/production_access.key
          /bin/mv /home/$USER_NAME/production_access.key /home/$USER_NAME/.ssh/production_access.key
        else
          echo "Production Access key NOT updated" >> /var/log/bastion/production_access_update.log
        fi
        /usr/sbin/usermod -aG bastion $USER_NAME
      fi
    fi
  fi
done < ~/keys_retrieved_from_s3
cat /dev/null >/home/$USER_NAME/.ssh/config
echo "Host *" >> /home/$USER_NAME/.ssh/config
echo "  User ubuntu" >> /home/$USER_NAME/.ssh/config
echo "  IdentityFile /home/$USER_NAME/.ssh/packer.key" >> /home/$USER_NAME/.ssh/config
echo "Host *prd.eu-west-1.aws*" >> /home/$USER_NAME/.ssh/config
echo "  User access" >> /home/$USER_NAME/.ssh/config
echo "  IdentityFile /home/$USER_NAME/.ssh/production_access.key" >> /home/$USER_NAME/.ssh/config
# Remove user accounts whose public key was deleted from S3
if [ -f ~/keys_installed ]; then
  sort -uo ~/keys_installed ~/keys_installed
  sort -uo ~/keys_retrieved_from_s3 ~/keys_retrieved_from_s3
  comm -13 ~/keys_retrieved_from_s3 ~/keys_installed | sed "s/\t//g" > ~/keys_to_remove
  while read line; do
    USER_NAME="`get_user_name "$line"`"
    echo "`date --date="today" "+%Y-%m-%d %H-%M-%S"`: Removing user account for $USER_NAME ($line)" >> $LOG_FILE
    /usr/sbin/userdel -r -f $USER_NAME
  done < ~/keys_to_remove
  comm -3 ~/keys_installed ~/keys_to_remove | sed "s/\t//g" > ~/tmp && mv ~/tmp ~/keys_installed
fi
EOF

chmod 700 /usr/bin/bastion/sync_users

/usr/bin/bastion/sync_users >> /var/log/bastion/sync_users_first_run.txt

###########################################
## SCHEDULE SCRIPTS AND SECURITY UPDATES ##
###########################################

cat > ~/mycron << EOF
*/5 * * * * /usr/bin/bastion/sync_s3
*/5 * * * * /usr/bin/bastion/sync_users
0 0 * * * yum -y update --security
EOF
crontab ~/mycron
rm ~/mycron
