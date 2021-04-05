#!/bin/bash

CRON_TAB_FILE=/etc/cron.d/mysqldump
CRON_USER_NAME=mysqldumper
CRON_USER_HOME=/srv/mysqldumper
DUMP_FOLDER=mysqldumps
DUMP_SCRIPT=mysqldump.sh

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function get_input() {
    local config_file=$3
    local config_key=$4
    local default_value=$5
    local is_input_secret=$1
    local prompt_message=$2
    local value

    # Get current value if available
    if [ -f "$config_file" ]; then
        value=$(cat "$config_file" | sed 's/ //g' | grep "^$config_key=" | cut -d= -f2)
    fi

    # Get default value if available
    if [ "$value" == "" ] && [ "$default_value" != "" ]; then
        value=$default_value
    fi

    # Append prompt message with current value if available
    if [ "$value" != "" ]; then
        if [ "$is_input_secret" == "1" ]; then
            prompt_message="$prompt_message [$(echo $value | sed 's/./*/g')]"
        else
            prompt_message="$prompt_message [$value]"
        fi
    fi

    # Get user input
    if [ "$is_input_secret" == "1" ]; then
        read -p "$prompt_message: " -s input
    else
        read -p "$prompt_message: " input
    fi

    if [ "$input" != "" ]; then
        value=$input
    fi

    echo $value
}

# Start message
echo -e "Installing MYSQLDUMP script for linux by Colin Ye - Installer v1.0\n"

# Prompt mysql information
echo To begin, enter the following MySql information required for mysqldump

mysql_host=$(get_input 0 Host $CRON_USER_HOME/.my.cnf host localhost)
mysql_port=$(get_input 0 Port $CRON_USER_HOME/.my.cnf port 3306)

mysql_user=$(get_input 0 User $CRON_USER_HOME/.my.cnf user)
while [ "$mysql_user" == "" ]; do
    mysql_user=$(get_input 0 User $CRON_USER_HOME/.my.cnf user)
done

mysql_pass=$(get_input 1 Password $CRON_USER_HOME/.my.cnf password)
printf "\n"
while [ "$mysql_pass" == "" ]; do
    mysql_pass=$(get_input 1 Password $CRON_USER_HOME/.my.cnf password)
    printf "\n"
done

echo -n "Testing MySql connection... "
mysql -h $mysql_host -P $mysql_port -u $mysql_user -p"$mysql_pass" -e "show databases" &>/dev/null
if [ $? -eq 0 ]; then
    echo Passed!
else
    echo Failed! Please verify your inputs and run this script again.
    exit 13
fi

# Prompt other information
function prompt_backup_info() {
    local cronjob_schedule_option
    local cronjob_schedule_custom
    local default_option=$2

    echo -e "\nHow often to perform a \`$1\` backup?
    0 - None
    1 - every hour
    2 - every day at 0400H
    3 - every day at 0000H and 1200H
    4 - every Sunday at 0400H
    5 - every month on the 1st at 0400H
    6 - Custom - You will edit the cronjob file later"
    read -p "Your choice [$default_option]: " cronjob_schedule_option
    while [ "$cronjob_schedule_option" != "" ] && \
            [ "$cronjob_schedule_option" != "1" ] && \
            [ "$cronjob_schedule_option" != "2" ] && \
            [ "$cronjob_schedule_option" != "3" ] && \
            [ "$cronjob_schedule_option" != "4" ] && \
            [ "$cronjob_schedule_option" != "5" ] && \
            [ "$cronjob_schedule_option" != "6" ] && \
            [ "$cronjob_schedule_option" != "0" ]; do
        read -p "Your choice [$default_option]: " cronjob_schedule
    done
    if [ "$cronjob_schedule_option" == "" ]; then
        cronjob_schedule_option=$default_option
    fi
    if [ "$cronjob_schedule_option" == "1" ]; then
        printf -v "cronjob_schedule_$1" "0 * * * *"
    elif [ "$cronjob_schedule_option" == "2" ]; then
        printf -v "cronjob_schedule_$1" "0 4 * * *"
    elif [ "$cronjob_schedule_option" == "3" ]; then
        printf -v "cronjob_schedule_$1" "0 0,12 * * *"
    elif [ "$cronjob_schedule_option" == "4" ]; then
        printf -v "cronjob_schedule_$1" "0 4 * * 0"
    elif [ "$cronjob_schedule_option" == "5" ]; then
        printf -v "cronjob_schedule_$1" "0 4 1 * *"
    else
        printf -v "cronjob_schedule_$1" "#* * * * *"
    fi

    if [ "$cronjob_schedule_option" != "0" ]; then
        printf -v "backup_count_$1" $(get_input 0 "How many copies of \`$1\` backup to keep?" - - 7)
    else
        printf -v "backup_count_$1" 7
    fi
}

prompt_backup_info full 2
prompt_backup_info split 0
printf "\n"

# Prompt zip password
zip_pass=$(get_input 1 "What password to use for 7z? (Leave blank for no password)")
printf "\n"
while [ ${#zip_pass} -gt 0 ] && [ ${#zip_pass} -le 4 ]; do
    echo -e "\n7z Password should be more than 4 characters."
    zip_pass=$(get_input 1 "What password to use for 7z? (Leave blank for no password)")
    printf "\n"
done
if [ "$zip_pass" != "" ]; then
    zip_pass_opt=-z\ \"${zip_pass//\"/\\\"}\"
else
    zip_pass_opt=""
fi

printf "\n"

# Setup cronjob user
cron_user_exists=$(grep -c ^$CRON_USER_NAME /etc/passwd)
if [ "$cron_user_exists" == "0" ]; then
    opt_group=""
    opt_shell="-s /bin/false"

    gid=$(getent group $CRON_USER_NAME | cut -d: -f3)
    if [ "$gid" != "" ]; then
        opt_group="-g $gid"
    fi

    echo -n "Adding system account \"$CRON_USER_NAME\"... "
    mkdir -p $CRON_USER_HOME
    useradd -r -d $CRON_USER_HOME $opt_shell $opt_group $CRON_USER_NAME
    echo Done!
fi

mkdir -p $CRON_USER_HOME
chown -R $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME
chmod 750 $CRON_USER_HOME

mkdir -p $CRON_USER_HOME/$DUMP_FOLDER
chown $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME/$DUMP_FOLDER
chmod 750 $CRON_USER_HOME/$DUMP_FOLDER

# Begin installation
echo Starting the installation process:

# Store mysql information
echo -n "Saving MySql configuration to \"$CRON_USER_HOME/.my.cnf\"... "
echo "[client]
host = $mysql_host
port = $mysql_port
user = $mysql_user
password = $mysql_pass" > $CRON_USER_HOME/.my.cnf
chown $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME/.my.cnf
chmod 640 $CRON_USER_HOME/.my.cnf
echo Done!

# Setup mysqldump script
echo -n "Generating mysqldump script \"$CRON_USER_HOME/$DUMP_SCRIPT\"... "
echo '#!/bin/bash

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M)
DIR="$(pwd)"
VERSION="MySqlDump Script for Linux by Colin Ye - v1.0 (5th April 2021)"

function housekeep() {
    FOLDERS=$(ls $backup_dir | grep -E "^MYSQL\.$1\.[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{4}\.$2\.7z$")
    CURRENT_COUNT=$(echo $FOLDERS | wc -w)
    REMOVE_COUNT=$((CURRENT_COUNT-backup_count))

    if [ $REMOVE_COUNT -gt 0 ]; then
        FILES_TO_DELETE=$(echo $FOLDERS | cut -d\  -f-$((REMOVE_COUNT)))
        for file in $FILES_TO_DELETE; do
            rm "$backup_dir/$file"
        done
    fi
}

# Check for dependencies
if ! command -v 7z &>/dev/null; then
    echo "Error: This script requires the package p7zip-full to be installed in your system"
    exit 1
fi

# Set options
option_key=""
backup_count=0
backup_dir="$DIR"
backup_type=full
zip_pass=""

for arg in "$@"; do
    if [ "$option_key" == "-t" ] || [ "$option_key" == "--type" ]; then
        if [ "$arg" == "full" ] ||  [ "$arg" == "split" ] || [ "$arg" == "both" ]; then
            backup_type=$arg
            option_key=""
        else
            echo Invalid backup type. Run the command with -h or --help for more details.
            exit 1
        fi
    elif [ "$option_key" == "-d" ] || [ "$option_key" == "--dir" ]; then
        if [[ ${arg:0:1} == "/" ]]; then
            backup_dir="$arg"
        else
            backup_dir="$DIR/$arg"
        fi
        option_key=""
    elif [ "$option_key" == "-k" ] || [ "$option_key" == "--housekeep" ]; then
        if [[ ! "$arg" =~ ^[0-9]+$ ]]; then
            echo Invalid option for $option_key. Run the command with -h or --help for more details.
            exit 1
        fi
        backup_count=$arg
        option_key=""
    elif [ "$option_key" == "-z" ] || [ "$option_key" == "--zip-pass" ]; then
        if [ ${#arg} -le 4 ]; then
            echo Zip password must be longer than 4 characters.
            exit 1
        fi
        zip_pass=-p"$arg"
        option_key=""
    elif [ "$arg" == "-d" ] || [ "$arg" == "--dir" ]; then
        option_key="$arg"
        backup_dir=""
    elif [ "$arg" == "-h" ] || [ "$arg" == "--help" ]; then
        echo -e "$VERSION\n"
        echo "Arguments"
        echo "    -d --dir <path>              Write the backup file to a different directory"
        echo "    -h --help                    Display the help section and exit"
        echo "    -k --housekeep <#>           Keep only the latest # copies in the directory"
        echo "    -t --type <full|split>       Specify the backup type; Default is \`full\` if not specified"
        echo "    -v --version                 Display the version details and exit"
        echo "    -z --zip-pass <password>     Set the password to protect the 7z archive"
        exit 0
    elif [ "$arg" == "-k" ] || [ "$arg" == "--housekeep" ]; then
        option_key="$arg"
        backup_count=""
    elif [ "$arg" == "-t" ] || [ "$arg" == "--type" ]; then
        option_key=$arg
        backup_type=""
    elif [ "$arg" == "-v" ] || [ "$arg" == "--version" ]; then
        echo "$VERSION"
        exit 0
    elif [ "$arg" == "-z" ] || [ "$arg" == "--zip-pass" ]; then
        option_key=$arg
        zip_pass=0
    else
        echo Invalid argument $arg. Run the command with -h or --help for more details.
        exit 1
    fi
done

# Check for errors
if [ "$backup_dir" == "" ]; then
    echo Please specify the backup directory. Run the command with -h or --help for more details.
    exit 1
elif [ ! -d "$backup_dir" ]; then
    echo Error: the directory \"$backup_dir\" does not exists
    exit 1
elif [ ! -w "$backup_dir" ]; then
    echo Error: no permission to write to \"$backup_dir\"
    exit 1
elif [ "$backup_type" == "" ]; then
    echo Please specify the backup type. Or omit the $option_key switch.
    echo Run the command with -h or --help for more details.
    exit 1
elif [ "$backup_count" == "" ]; then
    echo Please specify the number of backup copies to keep. Or omit the $option_key switch.
    echo Run the command with -h or --help for more details.
    exit 1
elif [ "$zip_pass" == "0" ]; then
    echo Please specify the password to protect 7z archives. Or omit the $option_key switch.
    echo Run the command with -h or --help for more details.
    exit 1
fi

# Full backup
if [ "$backup_type" == "full" ]; then
	mysqldump=$(mysqldump --no-tablespaces --all-databases) || exit 1
    echo "$mysqldump" | 7z a -si $zip_pass "$backup_dir/MYSQL.FULL.$DATE.$TIME.sql.7z" &>/dev/null
    if [ $? -ne 0 ]; then
        echo Error: the script has encountered an error during the 7z compression process
        exit 1
    fi
    chmod 640 "$backup_dir/MYSQL.FULL.$DATE.$TIME.sql.7z"

    if [ $backup_count -gt 0 ]; then
        housekeep FULL sql
    fi

# Split backup
elif [ "$backup_type" == "split" ]; then
	databases=$(mysql -e "show databases" | tail -n+2 | grep -v -e information_schema -e mysql -e performance_schema -e sys) || exit 1
	for db in $databases; do
		mkdir -p "$backup_dir/MYSQL.$DATE.$TIME"

		tables=$(mysql -D $db -e "show tables" | tail -n+2) || exit 1
		for table in $tables; do
			mysqldump --no-tablespaces $db $table > "$backup_dir/MYSQL.$DATE.$TIME/MYSQL.$DATE.$TIME.$db.$table.sql" || exit 1
		done
	done
	
    tar -C "$backup_dir" -cf - MYSQL.$DATE.$TIME --remove-files | 7z a -si $zip_pass "$backup_dir/MYSQL.SPLIT.$DATE.$TIME.tar.7z" &>/dev/null
    if [ $? -ne 0 ]; then
        echo Error: the script has encountered an error during the 7z compression process
        exit 1
    fi
    chmod 640 "$backup_dir/MYSQL.SPLIT.$DATE.$TIME.tar.7z"

    if [ $backup_count -gt 0 ]; then
        housekeep SPLIT tar
    fi
fi
' > $CRON_USER_HOME/$DUMP_SCRIPT
chown $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME/$DUMP_SCRIPT
chmod 750 $CRON_USER_HOME/$DUMP_SCRIPT
echo Done!

# Setup crontab
echo -n "Writing the cronjob schedule to \"$CRON_TAB_FILE\"... "
echo "$cronjob_schedule_full root su - $CRON_USER_NAME -s /bin/bash -c '$CRON_USER_HOME/$DUMP_SCRIPT -t full -d $CRON_USER_HOME/$DUMP_FOLDER -k $backup_count_full $zip_pass_opt'" > $CRON_TAB_FILE
echo "$cronjob_schedule_split root su - $CRON_USER_NAME -s /bin/bash -c '$CRON_USER_HOME/$DUMP_SCRIPT -t split -d $CRON_USER_HOME/$DUMP_FOLDER -k $backup_count_split $zip_pass_opt'" >> $CRON_TAB_FILE
chmod 644 $CRON_TAB_FILE
echo Done!

# End
echo -e "\nInstallation completed!"
echo To execute script manually, run \"$CRON_USER_HOME/$DUMP_SCRIPT -h\" for more information
