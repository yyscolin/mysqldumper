# MySqlDumper

## Mysqldump Script for Linux
Mysqldumper is a script to automate the backing up of a MySql database and 7-zipping it up.
Common practice is to compress using gzip but that does not offer password protection for the archive.

## Required Packages
p7zip-full

#### For Debian/ Ubuntu
sudo apt update && sudo apt install -y p7zip-full

## Instructions (with root/ sudo account)
- Clone the repository and run the installer
```
git clone https://github.com/yyscolin/mysqldumper.git /srv/mysqldumper
/srv/mysqldumper/mysqldumper-setup.sh
```
- Update the mysql credentials file `vim /srv/mysqldumper/my.cnf`
- Duplicate and edit the files in "backup_profiles" and "remote_drive_profiles" as neccessary
- Change ownership of /srv/mysqldumper `chown -R mysqldumper:mysqldumper /srv/mysqldumper`
- Edit the crontab accordingly `vim /etc/cron.d/mysqldump`

## Working Principles
Periodically run a backup and store it in the local and/or remote machine.

### Full Backup
Full backup refers to performing a mysqldump on all databases into a single .sql file before tar-zipping it up.

### Split Backup
For split backup, the script will perform backup of all non-system databases and create a seperate .sql file for __EACH TABLE__. All these .sql files will then be combined into a tar file before being zipped up by 7z.
