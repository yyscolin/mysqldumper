#!/bin/bash

declare -A DEFAULTS
DEFAULTS[backup_type]=full
DEFAULTS[local_dir]=/var/mysqldumps
DEFAULTS[local_filename]=mysqldump.%Y-%m-%d.%H%M%S

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
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
    local date_elements="a A b B c C d D e F g G h H I j k l m M n N p P q r R s S t T u U V w W x X y Y z :z ::z :::z Z"
    for x in $date_elements; do
        filename="${filename//\%$x/$(date +%$x)}"
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

[ "$backup_profile" == "" ] && throw_error missing argument: backup profile name

backup_profile_file="$dir/settings/backup_profiles/$backup_profile"
[ ! -f "$backup_profile_file" ] && throw_error missing file: $backup_profile_file

if ! command -v 7z &>/dev/null; then
    throw_error required package missing: p7zip-full
fi

DEFAULTS[local_dir]="${DEFAULTS[local_dir]}/$backup_profile"

while read line; do
    if [[ $line =~ ^\[.*\]*$ ]]; then
        rdrive_profile_name=${line:1:-1}
        read_rdrive_profile "$dir/settings/remote_drive_profiles/$rdrive_profile_name"
    elif [[ $line =~ ^[^\#].+$ ]]; then
        drives[-1]=${drives[-1]}"$line\n"
    fi
done < "$backup_profile_file"

for ((i = 0; i < ${#drives[@]}; i++)); do
    if [ $i == 0 ]; then # Local backup
        parameters="backup_type local_count local_dir local_filename zip_pass"
        for key in $parameters; do
            value="$(echo -e "${drives[$i]}" | grep ^$key= | tail -n1 | cut -d= -f2-)"
            [ "$value" == "" ] && value="${DEFAULTS[$key]}"
            printf -v $key %s "$value"
        done
        [ ${local_dir:0:1} != "/" ] && local_dir=$dir/$local_dir
        if [ ! -d "$local_dir" ]; then
            mkdir -p "$local_dir" || exit 1
        fi
        [ "$zip_pass" == "" ] && throw_error zip files must be protected by password
        [[ $zip_pass =~ \  ]] && throw_error illegal character: spaces are not allowed for zip password

        DEFAULTS[remote_filename]="$local_filename"

        local_filename=$(parse_filename $local_filename)
        rm -rf "$local_dir/mysqldumper" || exit 1
        rm -rf "$local_dir/mysqldumper.tar" || exit 1
        mkdir -p "$local_dir/mysqldumper" || exit 1

        if [ $backup_type == "full" ]; then
            mysqldump --defaults-extra-file="$dir/my.cnf" --no-tablespaces --all-databases > "$local_dir/mysqldumper/mysqldump.sql" || exit 1
        elif [ $backup_type == "split" ]; then
            databases=$(mysql --defaults-extra-file="$dir/my.cnf" -e "show databases" | tail -n+2 | grep -v -e information_schema -e mysql -e performance_schema -e sys) || exit 1
            for db in $databases; do
                tables=$(mysql --defaults-extra-file="$dir/my.cnf" -D $db -e "show tables" | tail -n+2) || exit 1
                for table in $tables; do
                    mysqldump --defaults-extra-file="$dir/my.cnf" --no-tablespaces $db $table > "$local_dir/mysqldumper/$db.$table.sql" || exit 1
                done
            done
        else
            throw_error "invalid setting(s): $backup_profile_file: backup type: $backup_type"
        fi

        pwd=$PWD
        cd "$local_dir"
        tar -cf "mysqldumper.tar" "mysqldumper"
        [ $? -ne 0 ] && throw_error tar process failed
        cd $pwd

        7z a -p$zip_pass "/$local_dir/$local_filename.tar.7z" "$local_dir/mysqldumper.tar" &>/dev/null
        if [ $? -ne 0 ]; then
            rm -rf "$local_dir/mysqldumper" || exit 1
            rm -rf "$local_dir/mysqldumper.tar" || exit 1
            throw_error 7z compression failed
        else
            rm -rf "$local_dir/mysqldumper" || exit 1
            rm -rf "$local_dir/mysqldumper.tar" || exit 1
        fi
    else # Remote upload
        parameters="remote_type auth_token remote_filename remote_count remote_folder"
        for key in $parameters; do
            value="$(echo -e "${drives[$i]}" | grep ^$key= | tail -n1 | cut -d= -f2-)"
            printf -v $key %s "$value"
        done

        [ "$remote_folder" == "" ] && remote_folder_parsed="" || remote_folder_parsed=", parents: [\"$remote_folder\"]"
        [ "$remote_filename" == "" ] && remote_filename=${DEFAULTS[remote_filename]}
        remote_filename=$(parse_filename "$remote_filename")

        curl -s -X POST -H "Authorization: Bearer $auth_token" \
                -F "metadata={name :\"$remote_filename.tar.7z\"$remote_folder_parsed};type=application/json;charset=UTF-8;" \
                -F "file=@$local_dir/$local_filename.tar.7z;type=application/zip" \
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" &>/dev/null

        if [ $remote_count != "" ]; then
            [ "$remote_folder" == "" ] && remote_folder=root
            files_url="https://www.googleapis.com/drive/v3/files?orderBy=createdTime&q=%22$remote_folder%22%20in%20parents%20and%20mimeType%20=%20%22application/zip%22"
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
    files=$(ls "$local_dir" | grep .tar.7z$)
    current_count=$(echo $files | wc -w)
    remove_count=$((current_count-local_count))

    if [ $remove_count -gt 0 ]; then
        files_to_delete=$(echo $files | cut -d\  -f-$((remove_count)))
        for file in $files_to_delete; do
            rm "$local_dir/$file"
        done
    fi
fi
