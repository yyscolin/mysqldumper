#!/bin/bash

CRON_TAB_FILE=/etc/cron.d/mysqldump
CRON_USER_NAME=mysqldumper
CRON_USER_HOME=/srv/mysqldumper
DUMP_FOLDER=mysqldumps
DUMP_SCRIPT=mysqldump.sh
PRESETS_FOLDER=presets

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
echo -e "Installing MYSQLDUMP script for linux by Colin Ye - Installer v1.01\n"

# Setup cronjob user
echo -n "Adding system account \"$CRON_USER_NAME\"... "
cron_user_exists=$(grep -c ^$CRON_USER_NAME /etc/passwd)
if [ "$cron_user_exists" == "0" ]; then
    opt_group=""
    opt_shell="-s /bin/false"

    gid=$(getent group $CRON_USER_NAME | cut -d: -f3)
    if [ "$gid" != "" ]; then
        opt_group="-g $gid"
    fi

    mkdir -p $CRON_USER_HOME
    useradd -r -d $CRON_USER_HOME $opt_shell $opt_group $CRON_USER_NAME
    echo Done!
else
    echo "Already exists; Skipping..."
fi

mkdir -p $CRON_USER_HOME
chown -R $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME
chmod 750 $CRON_USER_HOME

echo -n "Creating $CRON_USER_HOME/$DUMP_FOLDER... "
mkdir -p $CRON_USER_HOME/$DUMP_FOLDER
chown $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME/$DUMP_FOLDER
chmod 750 $CRON_USER_HOME/$DUMP_FOLDER
echo Done!

echo -n "Creating $CRON_USER_HOME/$PRESETS_FOLDER... "
mkdir -p $CRON_USER_HOME/$PRESETS_FOLDER
chown $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME/$PRESETS_FOLDER
chmod 750 $CRON_USER_HOME/$PRESETS_FOLDER
echo Done!

echo -n "Creating $CRON_TAB_FILE... "
touch -a $CRON_TAB_FILE
chmod 644 $CRON_TAB_FILE
echo Done!

# Setup mysqldump script
echo -n "Generating mysqldump script $CRON_USER_HOME/$DUMP_SCRIPT... "
echo '#!/bin/bash

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M)
DIR_SCRIPT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DIR="$(pwd)"
EXT=tar.7z
VERSION="MySqlDump Script for Linux by Colin Ye - v1.01 (15th April 2021)"

VALUES_UPLOAD_TO="google"
VALUES_BACKUP_TYPE="full split"

# Check for dependencies
if ! command -v 7z &>/dev/null; then
    echo "Error: This script requires the package p7zip-full to be installed in your system"
    exit 1
fi

# Default options
backup_count=0 #no housekeep
backup_dir="$DIR"
backup_type=full
remove_local=n

# Read arguments
option_key=""

for arg in "$@"; do
    # Set option key
    if [ "$arg" == "-d" ] || [ "$arg" == "--dir" ]; then
        option_key="$arg"
        key_backup_dir="$arg"
    elif [ "$arg" == "-h" ] || [ "$arg" == "--help" ]; then
        echo -e "$VERSION\n"
        echo "Arguments"
        echo "    -d --dir <directory>             Create the backup file in the specified directory"
        echo "    -h --help                        Display the help section and exit"
        echo "    -k --housekeep [#]               Keep only the latest # copies in the backup directory"
        echo "                                     Default is 30"
        echo "                                     0 = no housekeeping"
        echo "    -n --name-prefix <name>          Specify the prefix for backup file name"
        echo "    -p --profile <file>              Use the settings from the specified preset file"
        echo "    -r --remove-local [y|n]          Remove the local copy after uploading to cloud drive"
        echo "                                     Default is y"
        echo "    -t --type {full|split}           Specify the backup type"
        echo "    -u --upload-to {google}          Upload a copy of the created backup file to a cloud drive"
        echo "    -v --version                     Display the version details and exit"
        echo "    -z --zip-pass [<password>]       Set the password to protect the 7z archive"
        echo "                                     Blank = no password"
        exit 0
    elif [ "$arg" == "-k" ] || [ "$arg" == "--housekeep" ]; then
        option_key="$arg"
        key_backup_count="$arg"
    elif [ "$arg" == "-n" ] || [ "$arg" == "--name-prefix" ]; then
        option_key="$arg"
        key_name_prefix="$arg"
    elif [ "$arg" == "-p" ] || [ "$arg" == "--profile" ]; then
        option_key="$arg"
        key_backup_profile="$arg"
    elif [ "$arg" == "-r" ] || [ "$arg" == "--remove-local" ]; then
        option_key=$arg
        key_remove_local="$arg"
    elif [ "$arg" == "-t" ] || [ "$arg" == "--type" ]; then
        option_key=$arg
        key_backup_type="$arg"
    elif [ "$arg" == "-u" ] || [ "$arg" == "--upload-to" ]; then
        option_key="$arg"
        key_upload_to="$arg"
    elif [ "$arg" == "-v" ] || [ "$arg" == "--version" ]; then
        echo "$VERSION"
        exit 0
    elif [ "$arg" == "-z" ] || [ "$arg" == "--zip-pass" ]; then
        option_key=$arg
        key_zip_pass="$arg"

    # Set option value
    elif [ "$option_key" == "-d" ] || [ "$option_key" == "--dir" ]; then
        option_key=""
        arg_backup_dir="$arg"
    elif [[ "$arg" == -d* ]]; then
        key_backup_dir=-d
        arg_backup_dir=${arg:2}
    elif [ "$option_key" == "-k" ] || [ "$option_key" == "--housekeep" ]; then
        option_key=""
        arg_backup_count=$arg
    elif [[ "$arg" == -k* ]]; then
        key_backup_count=-k
        arg_backup_count=${arg:2}
    elif [ "$option_key" == "-n" ] || [ "$option_key" == "--name-prefix" ]; then
        option_key=""
        arg_name_prefix=$arg
    elif [[ "$arg" == -n* ]]; then
        key_name_prefix=-n
        arg_name_prefix=${arg:2}
    elif [ "$option_key" == "-p" ] || [ "$option_key" == "--profile" ]; then
        option_key=""
        backup_profile="$arg"
    elif [[ "$arg" == -p* ]]; then
        key_backup_profile=-p
        backup_profile=${arg:2}
    elif [ "$option_key" == "-r" ] || [ "$option_key" == "--remove-local" ]; then
        option_key=""
        arg_remove_local=$arg
    elif [[ "$arg" == -r* ]]; then
        key_remove_local=-r
        arg_remove_local=${arg:2}
    elif [ "$option_key" == "-t" ] || [ "$option_key" == "--type" ]; then
        option_key=""
        arg_backup_type=$arg
    elif [[ "$arg" == -t* ]]; then
        key_backup_type=-t
        arg_backup_type=${arg:2}
    elif [ "$option_key" == "-u" ] || [ "$option_key" == "--upload-to" ]; then
        option_key=""
        arg_upload_to="$arg"
    elif [[ "$arg" == -u* ]]; then
        key_upload_to=-u
        arg_upload_to=${arg:2}
    elif [ "$option_key" == "-z" ] || [ "$option_key" == "--zip-pass" ]; then
        option_key=""
        arg_zip_pass="$arg"
    elif [[ "$arg" == -z* ]]; then
        key_zip_pass=-z
        arg_zip_pass=${arg:2}

    # Invalid argument
    else
        echo Invalid argument $arg. Run the command with -h or --help for more details.
        exit 1
    fi
done

# Check for input errors
if [ "$key_backup_dir" != "" ] && [ "$arg_backup_dir" == "" ]; then
    echo Please specify the backup directory. Or omit the $key_backup_dir switch.
    echo Run the command with -h or --help for more details.
    exit 1
elif [ "$key_backup_type" != "" ] && [ "$arg_backup_type" == "" ]; then
    echo Please specify the backup type. Or omit the $key_backup_type switch.
    echo Run the command with -h or --help for more details.
    exit 1
elif [ "$key_backup_profile" != "" ] && [ "$backup_profile" == "" ]; then
    echo Please specify the backup profile. Or omit the $key_backup_profile switch.
    echo Run the command with -h or --help for more details.
    exit 1
elif [ "$key_name_prefix" != "" ] && [ "$arg_name_prefix" == "" ]; then
    echo Please specify the name prefix. Or omit the $key_name_prefix switch.
    echo Run the command with -h or --help for more details.
    exit 1
elif [ "$key_upload_to" != "" ] && [ "$arg_upload_to" == "" ]; then
    echo Please specify the upload destination. Or omit the $key_upload_to switch.
    echo Run the command with -h or --help for more details.
    exit 1
fi

# Parse path values
if [[ ${backup_profile:0:1} != "/" ]]; then
    backup_profile=$(realpath "$DIR/$backup_profile")
fi

if [[ ${arg_backup_dir:0:1} != "/" ]]; then
    arg_backup_dir=$(realpath "$DIR/$arg_backup_dir")
fi

# Get settings from backup profile
if [ ! -f "$backup_profile" ]; then
    echo Error: the backup profile \`$backup_profile\` settings file cannot be found.
    exit 1
fi

settings_backup_count=$(cat "$backup_profile" | tr -d " " | grep ^backup_count=)
if [ "$settings_backup_count" != "" ]; then
    backup_count=$(echo $settings_backup_count | head -n1 | cut -d= -f2-)
fi

settings_backup_dir=$(cat "$backup_profile" | tr -d " " | grep ^backup_dir=)
if [ "$settings_backup_dir" != "" ]; then
    backup_dir=$(echo $settings_backup_dir | head -n1 | cut -d= -f2-)
fi

settings_backup_type=$(cat "$backup_profile" | tr -d " " | grep ^backup_type=)
if [ "$settings_backup_type" != "" ]; then
    backup_type=$(echo $settings_backup_type | head -n1 | cut -d= -f2-)
fi

settings_name_prefix=$(cat "$backup_profile" | tr -d " " | grep ^name_prefix=)
if [ "$settings_name_prefix" != "" ]; then
    name_prefix=$(echo $settings_name_prefix | head -n1 | cut -d= -f2-)
fi

settings_upload_to=$(cat "$backup_profile" | tr -d " " | grep ^upload_to=)
if [ "$settings_upload_to" != "" ]; then
    upload_to=$(echo $settings_upload_to | head -n1 | cut -d= -f2-)
fi

settings_remove_local=$(cat "$backup_profile" | tr -d " " | grep ^remove_local=)
if [ "$settings_remove_local" != "" ]; then
    remove_local=$(echo $settings_remove_local | head -n1 | cut -d= -f2-)
fi

settings_zip_pass=$(cat "$backup_profile" | tr -d " " | grep ^zip_pass=)
if [ "$settings_zip_pass" != "" ]; then
    zip_pass=$(echo $settings_zip_pass | head -n1 | cut -d= -f2-)
fi

# Overwrite settings with values from arguments
if [ "$key_backup_count" != "" ] && [ "$arg_backup_count" == "" ]; then
    backup_count=30
elif [ "$arg_backup_count" != "" ]; then
    backup_count="$arg_backup_count"
fi

if [ "$arg_backup_dir" != "" ]; then
    backup_dir="$arg_backup_dir"
fi

if [ "$arg_backup_type" != "" ]; then
    backup_type="$arg_backup_type"
fi

if [ "$arg_name_prefix" != "" ]; then
    name_prefix="$arg_name_prefix"
fi

if [ "$arg_upload_to" != "" ]; then
    upload_to="$arg_upload_to"
fi

if [ "$key_remove_local" != "" ] && [ "$arg_remove_local" == "" ]; then
    remove_local=y
elif [ "$arg_remove_local" != "" ]; then
    remove_local="$arg_remove_local"
fi

if [ "$key_zip_pass" != "" ]; then
    zip_pass="$arg_zip_pass"
fi

# Check for logical errors
if [ ! -d "$backup_dir" ]; then
    echo Error: the directory \"$backup_dir\" does not exists
    exit 1
elif [ ! -w "$backup_dir" ]; then
    echo Error: no permission to write to \"$backup_dir\"
    exit 1
elif [[ ! ${VALUES_UPLOAD_TO[*]} =~ "$upload_to" ]]; then
    echo Error: invalid backup destination: \`$upload_to\`.
    if [ "$key_upload_to" != "" ]; then
        echo Run the command with -h or --help for more details.
    fi
    exit 1
elif [[ ! ${VALUES_BACKUP_TYPE[*]} =~ "$backup_type" ]]; then
    echo Error: invalid backup type \`$backup_type\`.
    if [ "$key_backup_type" != "" ]; then
        echo Run the command with -h or --help for more details.
    fi
    exit 1
elif [[ ! "$backup_count" =~ ^[0-9]+$ ]]; then
    echo Error: invalid backup count \`$backup_count\`: must be 0 or a positive integer.
    if [ "$key_backup_count" != "" ]; then
        echo Run the command with -h or --help for more details.
    fi
    exit 1
elif [ "$arg_zip_pass" != "" ] && [ ${#arg_zip_pass} -le 4 ]; then
    echo Error: zip password must be longer than 4 characters.
    echo Run the command with -h or --help for more details.
    exit 1
elif [ "$arg_zip_pass" == "" ] && [ "$settings_zip_pass" != "" ] && [ ${#settings_zip_pass} -le 4 ]; then
    echo Error: zip password must be longer than 4 characters.
    exit 1
elif [ "$remove_local" != "y" ] && [ "$remove_local" != "n" ]; then
    echo Error: Invalid valid for remove_local: \"$remove_local\": should only be \"y\" or \"n\".
    exit 1
elif [ "$remove_local" == "y" ] && [ "$upload_to" == "" ]; then
    echo Error: cannot remove local backup file unless uploading a cloud drive.
    exit 1
fi

# Set derived variables
if [ "$zip_pass" != "" ]; then
    zip_pass_opt=-p"$zip_pass"
fi

[ "$name_prefix" == "" ] && name_prefix=mysqldumper.$backup_type

# Init Google API; check errors and get auth token
if [ "$upload_to" == "google" ]; then
    client_id=$(cat "$backup_profile" | tr -d " " | grep ^client_id= | head -n1 | cut -d= -f2-)
    if [ "$client_id" == "" ]; then
        echo Error: Google client_id not specified in $backup_profile
        exit 1
    fi

    client_secret=$(cat "$backup_profile" | tr -d " " | grep ^client_secret= | head -n1 | cut -d= -f2-)
    if [ "$client_secret" == "" ]; then
        echo Error: Google client_secret not specified in $backup_profile
        exit 1
    fi

    refresh_token=$(cat "$backup_profile" | tr -d " " | grep ^refresh_token= | head -n1 | cut -d= -f2-)
    if [ "$refresh_token" == "" ]; then
        echo Error: Google refresh_token not specified in $backup_profile
        exit 1
    fi
    
    folder_id=$(cat "$backup_profile" | tr -d " " | grep ^folder_id= | head -n1 | cut -d= -f2-)
    if [ "$folder_id" == "" ]; then
        echo Error: Google folder ID not specified in $backup_profile
        exit 1
    fi

    # Generate new auth_token
    token_url=https://oauth2.googleapis.com/token
    auth_token=$(curl -s -d client_id=$client_id -d client_secret=$client_secret -d refresh_token=$refresh_token -d grant_type=refresh_token $token_url | grep "\"access_token\":" | tr -d " " | cut -d\" -f 4)
fi

# Full backup
if [ "$backup_type" == "full" ]; then
    mysqldump --no-tablespaces --all-databases > "$backup_dir/$name_prefix.$DATE.$TIME.sql" || exit 1
    tar -C "$backup_dir" -cf - $name_prefix.$DATE.$TIME.sql --remove-files | 7z a -si $zip_pass_opt "$backup_dir/$name_prefix.$DATE.$TIME.$EXT" &>/dev/null
    if [ $? -ne 0 ]; then
        echo Error: the script has encountered an error during the 7z compression process
        exit 1
    fi
    chmod 640 "$backup_dir/$name_prefix.$DATE.$TIME.$EXT"

# Split backup
elif [ "$backup_type" == "split" ]; then
	databases=$(mysql -e "show databases" | tail -n+2 | grep -v -e information_schema -e mysql -e performance_schema -e sys) || exit 1
	for db in $databases; do
		mkdir -p "$backup_dir/mysql.$DATE.$TIME"

		tables=$(mysql -D $db -e "show tables" | tail -n+2) || exit 1
		for table in $tables; do
			mysqldump --no-tablespaces $db $table > "$backup_dir/mysql.$DATE.$TIME/mysql.$DATE.$TIME.$db.$table.sql" || exit 1
		done
	done
	
    tar -C "$backup_dir" -cf - mysql.$DATE.$TIME --remove-files | 7z a -si $zip_pass_opt "$backup_dir/$name_prefix.$DATE.$TIME.$EXT" &>/dev/null
    if [ $? -ne 0 ]; then
        echo Error: the script has encountered an error during the 7z compression process
        exit 1
    fi
    chmod 640 "$backup_dir/$name_prefix.$DATE.$TIME.$EXT"
fi

# Upload to cloud drives
if [ "$upload_to" == "google" ]; then
    curl -s -X POST -H "Authorization: Bearer $auth_token" \
            -F "metadata={name :\"$name_prefix.$DATE.$TIME.$EXT\", parents: [\"$folder_id\"]};type=application/json;charset=UTF-8;" \
            -F "file=@$backup_dir/$name_prefix.$DATE.$TIME.$EXT;type=application/zip" \
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" &>/dev/null
fi

# Remove local copy
if [ "$remove_local" == "y" ]; then
    rm "$backup_dir/$name_prefix.$DATE.$TIME.$EXT"
fi

# Housekeeping
if [ $backup_count -gt 0 ]; then
    if [ "$upload_to" == "google" ]; then
        files_url="https://www.googleapis.com/drive/v3/files?orderBy=name&q=%22$folder_id%22%20in%20parents%20and%20name%20contains%20%22$name_prefix%22"
        files=$(curl -s -H "Authorization: Bearer $auth_token" $files_url | tr -d " " | grep ^\"id\": | cut -d\" -f4 )
        current_count=$(echo $files | wc -w)
        remove_count=$((current_count-backup_count))

        if [ $remove_count -gt 0 ]; then
            files_to_delete=$(echo $files | cut -d\  -f-$((remove_count)))
            for file_id in $files_to_delete; do
                curl -s -X DELETE -H "Authorization: Bearer $auth_token" https://www.googleapis.com/drive/v3/files/$file_id
            done
        fi
    fi

    if [ "$remove_local" != "y" ]; then
        files=$(ls $backup_dir | grep -E "^mysql\.$backup_type\.[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{4}\.$EXT$")
        current_count=$(echo $files | wc -w)
        remove_count=$((current_count-backup_count))

        if [ $remove_count -gt 0 ]; then
            files_to_delete=$(echo $files | cut -d\  -f-$((remove_count)))
            for file in $files_to_delete; do
                rm "$backup_dir/$file"
            done
        fi
    fi
fi
' > $CRON_USER_HOME/$DUMP_SCRIPT
chown $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME/$DUMP_SCRIPT
chmod 750 $CRON_USER_HOME/$DUMP_SCRIPT
echo Done!

# Prompt mysql information
echo -e "\nPlease enter the following MySql information:"

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

# Confirm existing profiles
preset_count=$(ls $CRON_USER_HOME/$PRESETS_FOLDER | wc -l)
if [ "$preset_count" -gt 0 ]; then
    echo -e "\nPlease confirm if you would like to keep the presets below:"
    for preset in "$CRON_USER_HOME/$PRESETS_FOLDER/"*; do
        prompt_message="$(echo $preset | cut -d/ -f5-)? (y|n) [y]: "
        read -p "$prompt_message" keep_preset
        while [ "$keep_preset" != y ] && [ "$keep_preset" != n ] && [ "$keep_preset" != "" ]; do
            echo Error: Invalid option. Please try again.
            read -p "$prompt_message" keep_preset
        done
        if [ "$keep_preset" == n ]; then
            rm -rf $preset
            preset=$preset'/settings.txt'
            preset=${preset//\//\\\/} # Escape /
            preset=${preset//\./\\\.} # Escape .
            sed -i "/.* -p $preset'/d" $CRON_TAB_FILE
        fi
    done
fi

# Prompt preset information
while true; do
    # Check if creating preset needed
    printf "\n"
    preset_count=$(ls $CRON_USER_HOME/$PRESETS_FOLDER | wc -l)
    if [ "$preset_count" == 0 ]; then
        echo "Creating your first preset..."
    else
        read -p "Would you like to create another preset? (y|n) [n]: " preset_create
        while [ "$preset_create" != y ] && [ "$preset_create" != n ] && [ "$preset_create" != "" ]; do
            echo Error: Invalid option. Please try again.
            read -p "Would you like to create another preset? (y|n) [n]: " preset_create
        done
        [[ "$preset_create" == n || "$preset_create" == "" ]] && break
    fi
    
    # Preset name
    preset_no=1
    while [ -d $CRON_USER_HOME/$PRESETS_FOLDER/Preset$preset_no ]; do
        preset_no=$((preset_no+1))
    done
    read -p "What would like to name this preset? [Preset$preset_no]: " preset_name
    if [ "$preset_name" == "" ]; then
        preset_name=Preset$preset_no
    fi

    # Cronjob schedule
    echo "How often to perform this backup?
    [1] - every hour
    [2] - every day at 0400H
    [3] - every day at 0000H and 1200H
    [4] - every Sunday at 0400H
    [5] - every month on the 1st at 0400H
    []  - Custom - You will edit the cronjob file later"
    read -p "Your choice []: " cronjob_schedule_option
    while [ "$cronjob_schedule_option" != "" ] && \
            [ "$cronjob_schedule_option" != "1" ] && \
            [ "$cronjob_schedule_option" != "2" ] && \
            [ "$cronjob_schedule_option" != "3" ] && \
            [ "$cronjob_schedule_option" != "4" ] && \
            [ "$cronjob_schedule_option" != "5" ]; do
        read -p "Your choice []: " cronjob_schedule_option
    done

    if [ "$cronjob_schedule_option" == "1" ]; then
        cronjob_schedule="0 * * * *"
    elif [ "$cronjob_schedule_option" == "2" ]; then
        cronjob_schedule="0 4 * * *"
    elif [ "$cronjob_schedule_option" == "3" ]; then
        cronjob_schedule="0 0,12 * * *"
    elif [ "$cronjob_schedule_option" == "4" ]; then
        cronjob_schedule="0 4 * * 0"
    elif [ "$cronjob_schedule_option" == "5" ]; then
        cronjob_schedule="0 4 1 * *"
    else
        cronjob_schedule="#* * * * *"
    fi

    # Housekeep info
    backup_count=$(get_input 0 "How many copies of this backup to keep?" - - 30)

    # Zip password info
    zip_pass=$(get_input 1 "What password to use for 7z? (Leave blank for no password)")
    printf "\n"
    while [ ${#zip_pass} -gt 0 ] && [ ${#zip_pass} -le 4 ]; do
        echo -e "\n7z Password should be more than 4 characters."
        zip_pass=$(get_input 1 "What password to use for 7z? (Leave blank for no password)")
        printf "\n"
    done

    # Create preset folder
    mkdir -p $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name
    chown $CRON_USER_NAME:$CRON_USER_NAME $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name
    chmod 750 $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name

    # Save configuration
    echo -n "Saving settings to \"$CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt\"... "
    echo "name_prefix=mysqldumper.$preset_name" > $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
    echo "backup_dir=$CRON_USER_HOME/$DUMP_FOLDER" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
    echo "backup_count=$backup_count" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
    if [ "$zip_pass" != "" ]; then
        zip_pass=${zip_pass//\"/\\\"} # Escape /
        echo "zip_pass=$zip_pass" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
    fi
    echo Done!
    echo -n "Writing cronjob schedule to \"$CRON_TAB_FILE\"... "
    echo "$cronjob_schedule root su - $CRON_USER_NAME -s /bin/bash -c '$CRON_USER_HOME/$DUMP_SCRIPT -p $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt'" >> $CRON_TAB_FILE
    echo Done!

    # Google Drive
    printf "\n"
    read -p "Would you also like to upload a copy of the backup file to Google Drive? (y|n) [n]: " upload_to_google
    while [ "$upload_to_google" != y ] && [ "$upload_to_google" != n ] && [ "$upload_to_google" != "" ]; do
        echo Error: Invalid option! Please try again.
        read -p "Would you also like to upload a copy of the backup file to Google Drive? (y|n) [n]: " upload_to_google
    done
    if [ "$upload_to_google" == y ]; then
        echo Please provide the following information for Google Drive API:
        read -p "Client ID: " client_id
        read -p "Client secret: " client_secret
        read -p "Refresh token: " refresh_token
        read -p "Folder ID: " folder_id
        echo -n "Saving Google Drive configurations to \"$CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt\"... "
        echo "upload_to=google" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
        echo "client_id=$client_id" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
        echo "client_secret=$client_secret" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
        echo "refresh_token=$refresh_token" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
        echo "folder_id=$folder_id" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
        echo Done!
    fi

    # Remove local
    if [ "$upload_to_google" == y ]; then
        printf "\n"
        read -p "Would you like to remove the local copy after uploading to cloud drive(s)? (y|n) [n]: " remove_local
        while [ "$remove_local" != y ] && [ "$remove_local" != n ] && [ "$remove_local" != "" ]; do
            echo Error: Invalid option! Please try again.
            read -p "Would you like to remove the local copy after uploading to cloud drive(s)? (y|n) [n]: " remove_local
        done
        if [ "$remove_local" == y ]; then
            echo -n "Updating the settings in \"$CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt\"... "
            echo "remove_local=y" >> $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt
            echo Done!
        fi
    fi

    # Done
    printf "\n"
    echo Preset configuration done! Please try the below command after the installation:
    echo sudo su - $CRON_USER_NAME -s /bin/bash -c \'$CRON_USER_HOME/$DUMP_SCRIPT -p $CRON_USER_HOME/$PRESETS_FOLDER/$preset_name/settings.txt\'
done

# End
echo -e "\nInstallation completed!"
echo To execute script manually, run \"$CRON_USER_HOME/$DUMP_SCRIPT -h\" for more information
