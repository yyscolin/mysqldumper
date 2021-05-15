# MySqlDumper

## Mysqldump Script for Linux v1.02
Mysqldumper is a script to automate the backing up of a MySql database and 7-zipping it up.
Common practice is to compress using gzip but that does not offer pass protection for the archive.

## Required Packages
p7zip-full

#### For Debian/ Ubuntu
sudo apt update && sudo apt install -y p7zip-full

## Instructions
- Create a MySql user with the privileges of performing a usual mysqldump backup
- Download mysqldumper-install.sh
- Run the install script using sudo privilege
- Answer the questions that you are prompted
- [Optional] Edit the crontab `/etc/cron.d/mysqldump`
- [Optional] Add users to the `mysqldumper` group
- [Optional] To upload backups to a cloud drive, edit the backup profile and add `upload-to=<drive-settings-fullpath>:<cloud-folder>`
- Done!

## Working Principles
The installer will create system account to periodically run a backup and store it in `/srv/mysqldumper/mysqldumps`.

### Full Backup
Full backup refers to performing a mysqldump on all databases into a single .sql file before tar-zipping it up.

### Split Backup
For split backup, the script will perform backup of all non-system databases and create a seperate .sql file for __EACH TABLE__. All these .sql files will then be combined into a tar file before being zipped up by 7z.

## Manual Execution
The installer creates a shell script `/srv/mysqldumper/mysqldump.sh` which can be used to create a backup (in the directory that you're currently in).

If can choose to manually run the script using the following arguments:
|Argument                     |Purpose                                                      |
|-----------------------------|-------------------------------------------------------------|
|-d --dir <directory>         |Create the backup file in the specified directory            |
|-h --help                    |Display the help section and exit                            |
|-k --housekeep [#]           |Keep only the latest # copies in the backup directory        |
|                             |Default is 30                                                |
|                             |0 = no housekeeping                                          |
|-n --name-prefix <name>      |Specify the prefix for backup file name                      |
|-p --profile <file>          |Use the settings from the specified preset file              |
|-r --remove-local [y\|n]     |Remove the local copy after uploading to cloud drive         |
|                             |Default is y                                                 |
|-t --type {full\|split}      |Specify the backup type                                      |
|-u --upload-to {google}      |Upload a copy of the created backup file to a cloud drive    |
|-v --version                 |Display the version details and exit                         |
|-z --zip-pass [\<password\>] |Set the password to protect the 7z archive                   |
|                             |Blank = no password                                          |
