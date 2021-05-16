# MySqlDumper

## Mysqldump Script for Linux
Mysqldumper is a script to automate the backing up of a MySql database and 7-zipping it up.
Common practice is to compress using gzip but that does not offer password protection for the archive.

## Required Packages
p7zip-full

#### For Debian/ Ubuntu
sudo apt update && sudo apt install -y p7zip-full

## Instructions
- Clone this repository
- Create my.cnf with mysql credentials in the folder
- Set permission to 640 for my.cnf
- Duplicate the file `backup-profiles/example` and edit accorindingly
- If remote drives are used, duplicated and edit the neccesary files in the folder `remote_drive_profiles`
- Create a linux service account for the cronjob `useradd -r -d -M -s /bin/false mysqldumper`
- Create a cronjob file `/etc/cron.d/mysqldump` with the cronjob entries. For example:
```
* * * * * root su - mysqldumper -s /bin/bash -c '/full/path/to/script/mysqldump.sh backup_profile_name'
```

## Working Principles
Periodically run a backup and store it in the local and/or remote machine.

### Full Backup
Full backup refers to performing a mysqldump on all databases into a single .sql file before tar-zipping it up.

### Split Backup
For split backup, the script will perform backup of all non-system databases and create a seperate .sql file for __EACH TABLE__. All these .sql files will then be combined into a tar file before being zipped up by 7z.
