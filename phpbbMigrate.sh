#!/bin/bash

# phpBB Automated and Direct Login to Administration Control Panel
# If your phpBB version works with cookies, try to use the the "-c" option in curl to write a cookie-file
# and the "-b" command to load a cookie-file

WORKDATE=`date +'%Y%m%d-%T'`
WORKDAY=`date +'%Y%m%d'`

source ini/settings.ini
git clone https://github.com/AnatolyUss/FromMySqlToPostgreSql.git my2pg

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
exit 0;
}

getAttachments()
{
FILE_IDS=`psql -At -U $PGUSER -p $PGPORT $DBNAME -c "select attach_id from phpbb_attachments;"`

for FILE_ID in ${FILE_IDS};
do
curl -s -b cookie.txt -d "redirect=./../download/file.php" \
        --user-agent "$USERAGENT" \
        "${ATTACHURL}${FILE_ID}" -o "${FILE_ID}"
done
}

getAvatarADU()
{
AVATARS_ADU=`select user_avatar from phpbb_users where user_avatar_type='avatar.driver.upload';`
for AVATAR_ADU in ${AVATARS_ADU};
do
curl -s -b cookie.txt -d "redirect=./../download/file.php" \
       	--user-agent "$USERAGENT" \
       	"${AVATARURL}${AVATAR_ADU}" -o "avatars_adu/${AVATAR_ADU}"
done
}




 authPhpBB
# getBackups
# loadSql

# cleanup
rm -rf cookie.txt
rm -rf adm_cookie.txt
rm -rf login_adm2.html
rm -rf login_adm.html
rm -rf login.html
echo "Cleanup cookies, HTML, etc done. Exiting."
