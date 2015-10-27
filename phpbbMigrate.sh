#!/bin/bash



# phpBB Automated and Direct Login to Administration Control Panel
# If your phpBB version works with cookies, try to use the the "-c" option in curl to write a cookie-file
# and the "-b" command to load a cookie-file

WORKDATE=`date +'%Y%m%d-%T'`
WORKDAY=`date +'%Y%m%d'`

source ini/settings.ini


configMy2Pg()
{
git clone https://github.com/AnatolyUss/FromMySqlToPostgreSql.git my2pg

echo "Checking for $DBNAME on $PGPORT"

PGRES=`psql -At -U ${PGUSER} -h ${PGHOST} -p ${PGPORT} ${DBNAME} -c "select now();"`
RET=$?
if [ $RET -eq 0 ]
then
 echo "Looks like $DBNAME exists, good."
else
 echo "Something's wrong, check setup, perhaps you haven't created $DBNAME on $PGHOST port $PGPORT"
 echo "Verify config or try 'createdb -U ${PGUSER} -h ${PGHOST} ${DBNAME}'"
fi

echo "Checking for $MYDB on $MYSQLPORT"
MYRES=`mysql -u $MYSQLUSR -p"${MYSQLPASS}" ${MYDB} -e "select now();"`
RET=$?
if [ $RET -eq 0 ]
then
 echo "Looks like $MYDB exists, good."
else
 echo "Something's wrong, check setup, perhaps you haven't created $MYDB on port $MYSQLPORT"
 echo "Verify config or try 'mysql -u $MYSQLUSR -p"${MYSQLPASS}" ${MYDB}'"
fi

cat << EOF > ${MY2PGCONF}
{
    "source_description" : [
        "Connection string to your MySql database"
    ],
    "source" : "mysql:host=${MYSQLHOST};port=${MYSQLPORT};dbname=${MYDB},${MYSQLUSR},${MYSQLPASS}",
    
    "target_description" : [
        "Connection string to your PostgreSql database"
    ],
    "target" : "pgsql:host=${PGHOST};port=${PGPORT};dbname=${DBNAME},${PGUSER},${PGPASS}",
    
    "encoding_description" : [
        "Encoding type of your PostgreSql database.",
        "If not supplied, then UTF-8 will be used as a default."
    ],
    "encoding" : "UTF-8",
    
    "schema_description" : [
        "schema - a name of the schema, that will contain all migrated tables.",
        "If not supplied, then a new schema will be created automatically."
    ],
    "schema" : "public",
    
    "data_chunk_size_description" : [
        "During migration each table's data will be split into chunks of data_chunk_size (in MB).",
        "If not supplied, then 10 MB will be used as a default."
    ],
    "data_chunk_size" : 10
}
EOF
echo "Wrote out ${MY2PGCONF}"

cat << EOF > my2pg_migration_command.sh
$(which php)   my2pg/index.php   ${MY2PGCONF}
EOF

echo "Wrote out migration_command.sh"


}


authPhpBB()
{
LOGINURL="${PHPBBFORUMROOT}/ucp.php?mode=login"
LOGINURL_ADM="${PHPBBFORUMROOT}/adm/index.php"

ATTACHURL="${PHPBBFORUMROOT}/download/file.php?id="
AVATARURL="${PHPBBFORUMROOT}/download/file.php?avatar="

BOARDURL="${PHPBBFORUMROOT}/index.php"
# IMPORTANT: In this script you have to use the same User Agent as your Browser does, otherwise it won't work.
# find it out for example on: http://www.whatsmyuseragent.com/
USERAGENT="Mozilla/5.0 (X11; Linux i686; rv:41.0) Gecko/20100101 Firefox/41.0"


# Login to phpBB like a normal user
curl -s -c cookie.txt -d "username=$USERNAME" \
       	-d "password=$PASSWORD" \
        -d "login=Login" --user-agent "$USERAGENT" $LOGINURL -o "login.html"

# Get Session ID for this Login
SID=$(egrep  -o "sid.*\>" login.html | sed -n '1p' | sed 's/sid=//')
echo "sid= $SID"


# Now go to the Administration Control Panel Login Area
curl -s --user-agent "$USERAGENT" "$LOGINURL_ADM?sid=$SID" -o "login_adm.html"

# And get the "credential"-value, which is essential
credential=$(egrep  -o "credential.*\>" login_adm.html | sed -n '1p' | sed 's/credential" value="//')
echo "credential=$credential"

# Login to the Administration Control Panel, POST all essential data including the "credential"-value
curl -s -c adm_cookie.txt -d "credential=$credential" \
        -d "login=Login" \
        -d "username=$USERNAME" \
        -d "password_$credential=$PASSWORD" \
        -d "redirect=./../adm/index.php?sid=$SID" \
        --user-agent "$USERAGENT" "$LOGINURL_ADM?sid=$SID" -o "login_adm2.html"

echo ""
# Let's see, if everything worked:
# Error:
cat login_adm2.html | grep "Access to the Administration Control Panel is not allowed as you do not have administrative permissions." | sed 's/\t<p>//' | sed 's/<\/p>.*//'
# Success:
cat login_adm2.html | grep "You have successfully authenticated and will now be redirected to the Administration Control Panel." | sed 's/\t<p>//' | sed 's/<br \/>.*//'

# Get the new Session ID:
SID_ADM=$(egrep  -o "sid.*\>" login_adm2.html | sed -n '1p' | sed 's/sid=//')
echo "old sid = $SID"
echo "new sid = $SID_ADM"
}

getBackups()
{
TABLENAMES=$(<${TABLESBAK})

mkdir -p ${BAKDIR}

for TABLENAME in $TABLENAMES;
do
TABLESAVE=${BAKDIR}/${TABLENAME}.${OUT}

curl -s -# -b adm_cookie.txt \
       -d "redirect=./../adm/index.php?sid=${SID_ADM}" \
       --user-agent "$USERAGENT" \
       -X POST -d "type=${TYPE}&method=${METHOD}&where=download&table%5B%5D=${TABLENAME}&submit=Submit" \
       "$LOGINURL_ADM?sid=${SID_ADM}&i=database&mode=backup&action=download" -o "${TABLESAVE}"
RET=$?
 if [ $RET -eq 0 ]
   then
    echo OK: ${TABLESAVE}
   else
    echo ERROR: ${TABLESAVE}
 fi

done

echo "Check if Errors, otherwise - done."

}


loadSql()
{

echo "In LoadSQL, cd ${BAKDIR}"
cd ${BAKDIR}

ARCHIVEFILES=`ls *.${OUT}`

gunzip $ARCHIVEFILES

SQLFILES=`ls *.sql`

for file in $SQLFILES;
do

mysql -u $MYSQLUSR -p"${MYSQLPASS}" ${MYDB} < $file
RET=$?

if [ $RET -ne 0 ]; then
echo "FAIL: $file"
else
echo "OK: $file"
fi

done;
}

getAttachments()
{
mkdir attachments

FILE_IDS=`psql -At -U $PGUSER -h $PGHOST -p $PGPORT $DBNAME -c "select attach_id from phpbb_attachments limit 10;"`

for FILE_ID in ${FILE_IDS};
do
curl -s -b cookie.txt -d "redirect=./../download/file.php" \
        --user-agent "$USERAGENT" \
        "${ATTACHURL}${FILE_ID}" -o "attachments/${FILE_ID}"
done

}


getAvatarADU()
{
mkdir avatars_adu

AVATARS_ADU=`psql -At -U $PGUSER -h $PGHOST -p $PGPORT $DBNAME -c "select user_avatar from phpbb_users where user_avatar_type='avatar.driver.upload';"`

for AVATAR_ADU in ${AVATARS_ADU};
do
curl -s -b cookie.txt -d "redirect=./../download/file.php" \
       	--user-agent "$USERAGENT" \
       	"${AVATARURL}${AVATAR_ADU}" -o "avatars_adu/${AVATAR_ADU}"
done
}

while getopts f: option
do
        case "${option}"
        in
                f) FUNC=$OPTARG;;
                *} `echo "Pass an option i.e. -f getBackups, loadSql, configMy2Pg, getAttachments, getAvatarADU"`;;
        esac
done



authPhpBB



`${FUNC}`

# getBackups
# loadSql
# configMy2Pg

# getAttachments
# getAvatarADU



# cleanup
rm -rf cookie.txt
rm -rf adm_cookie.txt
rm -rf login_adm2.html
rm -rf login_adm.html
rm -rf login.html
echo "Cleanup cookies, HTML, etc done. Exiting."

#with recursive forums as(
#select 1 as level, forum_id as parent, forum_name from phpbb_forums
#where parent_id=0
#UNION ALL
#select 2, parent_id, '  ---'||forum_name from phpbb_forums
#where parent_id > 0
#)
#select forum_name
#from forums
#group by parent,forum_name,level
#order by parent,level;
