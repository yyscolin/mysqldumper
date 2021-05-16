#!/bin/bash

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
VERSION="MySqlDump Script for Linux by Colin Ye - v2 (15th May 2021)"
REMOTE_DRIVE_VALUES="google"

backup_profile="$1"
drives=("")

function throw_error() {
    local msg="mysqldumper: error:"
    for arg in "$@"; do msg=$msg' '$arg; done
    echo $msg
    exit 1
}

function parse_filename() {
    local filename="$1"
    local mode=0 # 0 = normal; 1 = regex; 2 = wildcard
    [ "$2" != "" ] && mode=$2

    [ $mode == 1 ] && filename="${filename//\./\\\.}"

    local date_elements="a A b B c C d D e F g G h H I j k l m M n N p P q r R s S t T u U V w W x X y Y z :z ::z :::z Z"
    for x in $date_elements; do
        if [ $mode == 1 ]; then
            filename="${filename//\%$x/.*}"
        elif [ $mode == 2 ]; then
            filename="${filename//\%$x/\*}"
        else
            filename="${filename//\%$x/$(date +%$x)}"
        fi
    done

    echo $filename
}

function read_rdrive_profile() {
    local file="$1"
    local required_parameters="remote_type client_id client_secret refresh_token"
    
    [ ! -f "$file" ] && throw_error file not found: $file
    for key in $required_parameters; do
        value=$(cat "$file" | grep ^$key=.*$ | tail -n1 | cut -d= -f2-)
        [ "$value" == "" ] && throw_error missing value: $file: $key
        printf -v $key %s "$value"
    done

    is_auth_expired=y
    auth_expiry=$(cat "$file" | grep ^auth_expiry= | tail -n1 | cut -d= -f2-)
    if [ "$auth_expiry" != "" ]; then
        datetime_now=$(date +%s)
        [ $(( datetime_now - auth_expiry )) -le 0 ] && is_auth_expired=n
    fi

    if [ $is_auth_expired == y ]; then
        sed -i "/^auth_token=.*/d" "$file"
        sed -i "/^auth_expiry=.*/d" "$file"

        token_url=https://oauth2.googleapis.com/token
        curl_response=$(curl -s -d client_id=$client_id -d client_secret=$client_secret -d refresh_token=$refresh_token -d grant_type=refresh_token $token_url)
        auth_token=$(echo $curl_response | grep -o \"access_token\":\ [^,]* | cut -d\" -f 4)
        auth_expires_in=$(($(echo $curl_response | grep -o \"expires_in\":\ [^,]* | cut -d\  -f 2)-300))
        auth_expiry=$(date -d "+$auth_expires_in seconds" +%s)
        echo "auth_token=$auth_token" >> "$file"
        echo "auth_expiry=$auth_expiry" >> "$file"
    else
        auth_token=$(cat "$file" | grep ^auth_token= | tail -n1 | cut -d= -f2-)
    fi

    drives+=("remote_type=$remote_type\nauth_token=$auth_token\n")
}

if [ "$backup_profile" == "" ]; then
    throw_error missing argument: backup profile name
else
    backup_profile_file="$DIR_SCRIPT/settings/backup_profiles/$backup_profile"
    [ ! -f "$backup_profile_file" ] && throw_error missing file: $backup_profile_file
fi

if ! command -v 7z &>/dev/null; then
    throw_error required package missing: p7zip-full
fi

while read line; do
    line_count=$(( line_count+1 ))
    if [[ $line =~ ^\[.*\]*$ ]]; then
        rdrive_profile_name=${line:1:-1}
        read_rdrive_profile "$DIR_SCRIPT/settings/remote_drive_profiles/$rdrive_profile_name"
    elif [[ $line =~ ^[^\#].+$ ]]; then
        drives[-1]=${drives[-1]}"$line\n"
    fi
done < "$backup_profile_file"

for ((i = 0; i < ${#drives[@]}; i++)); do
    if [ $i == 0 ]; then # Local backup
        parameters="backup_type local_count local_dir local_filename zip_pass"
        for key in $parameters; do
            value="$(echo -e "${drives[$i]}" | grep ^$key= | tail -n1 | cut -d= -f2-)"
            printf -v $key %s "$value"
        done
        [ "$backup_type" == "" ] && backup_type=full
        [ "$local_dir" == "" ] && local_dir="$DIR_SCRIPT/mysqldumps"
        [ ${local_dir:0:1} != "/" ] && local_dir=$DIR_SCRIPT/$local_dir
        [ "$local_filename" == "" ] && local_filename="mysqldumper.%Y-%m-%d.%H%M%S"
        local_filename_parsed=$(parse_filename $local_filename)
        [ "$zip_pass" != "" ] && zip_pass=-p$zip_pass
        
        mkdir -p "$local_dir"

        if [ $backup_type == "full" ]; then
            mysqldump --defaults-extra-file="$DIR_SCRIPT/my.cnf" --no-tablespaces --all-databases > "$local_dir/$local_filename_parsed.sql" || exit 1
            tar -C "$local_dir" -cf - $local_filename_parsed.sql --remove-files | 7z a -si "$zip_pass" "$local_dir/$local_filename_parsed.tar.7z" &>/dev/null
            if [ $? -ne 0 ]; then
                echo mysqldumper: error: process failure: 7z compression
                exit 1
            fi

        elif [ $backup_type == "split" ]; then
            databases=$(mysql -e "show databases" | tail -n+2 | grep -v -e information_schema -e mysql -e performance_schema -e sys) || exit 1
            for db in $databases; do
                mkdir -p "$local_dir/$local_filename_parsed"

                tables=$(mysql -D $db -e "show tables" | tail -n+2) || exit 1
                for table in $tables; do
                    mysqldump --defaults-extra-file="$DIR_SCRIPT/my.cnf" --no-tablespaces $db $table > "$local_dir/$local_filename_parsed/$db.$table.sql" || exit 1
                done
            done
            
            tar -C "$local_dir" -cf - $local_filename_parsed --remove-files | 7z a -si "$zip_pass" "$local_dir/$local_filename_parsed.tar.7z" &>/dev/null
            if [ $? -ne 0 ]; then
                echo mysqldumper: error: process failure: 7z compression
                exit 1
            fi
        
        else
            echo mysqldumper: error: invalid value: backup profile settings: backup type: $backup_type
            exit 1
        fi
    else # Remote upload
        parameters="remote_type auth_token remote_filename remote_count remote_folder"
        for key in $parameters; do
            value="$(echo -e "${drives[$i]}" | grep ^$key= | tail -n1 | cut -d= -f2-)"
            printf -v $key %s "$value"
        done

        [ "$remote_count" == "" ] && remote_count=$local_count
        [ "$remote_folder" != "" ] && remote_folder_parsed=", parents: [\"$remote_folder\"]" || remote_folder_parsed=""
        [ "$remote_filename" == "" ] && remote_filename=$local_filename
        remote_filename_parsed=$(parse_filename "$remote_filename")
        remote_filename_wildcard=$(parse_filename "$remote_filename" 2)

        curl -s -X POST -H "Authorization: Bearer $auth_token" \
                -F "metadata={name :\"$remote_filename_parsed.tar.7z\"$remote_folder_parsed};type=application/json;charset=UTF-8;" \
                -F "file=@$local_dir/$local_filename_parsed.tar.7z;type=application/zip" \
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" &>/dev/null

        if [ $remote_count != "" ]; then
            [ "$remote_folder" == "" ] && remote_folder=root
            files_url="https://www.googleapis.com/drive/v3/files?orderBy=name&q=%22$remote_folder%22%20in%20parents%20and%20name%20contains%20%22$remote_filename_wildcard%22"
            files=$(curl -s -H "Authorization: Bearer $auth_token" $files_url | tr -d " " | grep ^\"id\": | cut -d\" -f4 )
            current_count=$(echo $files | wc -w)
            remove_count=$((current_count-remote_count))
            if [ $remove_count -gt 0 ]; then
                files_to_delete=$(echo $files | cut -d\  -f-$((remove_count)))
                for file_id in $files_to_delete; do
                    curl -s -X DELETE -H "Authorization: Bearer $auth_token" https://www.googleapis.com/drive/v3/files/$file_id
                done
            fi
        fi
    fi
done

# Local housekeeping
if [ "$local_count" != "" ]; then
    local_filename_regexp=$(parse_filename $local_filename 1)
    files=$(ls $local_dir | grep -E "^$local_filename_regexp\.tar\.7z$")
    current_count=$(echo $files | wc -w)
    remove_count=$((current_count-local_count))

    if [ $remove_count -gt 0 ]; then
        files_to_delete=$(echo $files | cut -d\  -f-$((remove_count)))
        for file in $files_to_delete; do
            rm "$local_dir/$file"
        done
    fi
fi
