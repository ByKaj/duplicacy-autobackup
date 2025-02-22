#!/bin/sh


: ${B2_ID:?"Missing B2 ID"}
: ${B2_KEY:?"Missing B2 key"}

TEST_BUCKET=duplicacy-autobackup-tests
BACKUP_LOCATION="b2://$TEST_BUCKET"
IMAGE_NAME=duplicacy-autobackup # local image
PASSPHRASE='correct horse battery staple'
BACKUP_NAME='test-backups'
temp_dir=$(mktemp -d)

if [[ ! -z $(aws s3 ls $TEST_BUCKET) ]]; then
    echo "Test bucket is not empty. Exiting" >&2
    exit 1
fi

cleanup() {
    echo 'Cleaning up...'
    aws b2 rm s3://$TEST_BUCKET/ --recursive
    docker rm -f duplicacy-autobackup
    rm -rf $temp_dir 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p $temp_dir/data
echo "hello, world" > $temp_dir/data/hello.txt

docker run -d --name duplicacy-autobackup \
    -v $temp_dir/data:/data \
    -e BACKUP_NAME=$BACKUP_NAME \
    -e BACKUP_LOCATION="$BACKUP_LOCATION" \
    -e BACKUP_SCHEDULE='0 2 * * *' \
    -e BACKUP_IMMEDIATELY='yes' \
    -e BACKUP_ENCRYPTION_KEY="$PASSPHRASE" \
    -e B2_ID=$B2_ID \
    -e B2_KEY=$B2_KEY \
    $IMAGE_NAME

echo "Waiting for backup to be performed..."
sleep 20

if [[ -z $(aws b2 ls $TEST_BUCKET) ]]; then
    echo "Nothing in test bucket. Exiting" >&2
    exit 2
fi

if [[ ! -d $temp_dir/data/.duplicacy ]]; then
    echo "No duplicacy folder created. Exiting" >&2
    exit 3
fi

echo "Backup performed"

# Try a restore
echo "Performing restore..."
mkdir -p $temp_dir/restore
cd $temp_dir/restore

export DUPLICACY_PASSWORD="$PASSPHRASE"
export DUPLICACY_B2_ID="$B2_ID"
export DUPLICACY_B2_SECRET="$B2_KEY"
duplicacy init -encrypt $BACKUP_NAME $BACKUP_LOCATION
duplicacy restore -r 1

status=0
if [[ -f ./hello.txt ]]; then 
    echo "Restore successful"
else
    echo "Failed to perform restore" >&2
    status=4
fi

exit $status
