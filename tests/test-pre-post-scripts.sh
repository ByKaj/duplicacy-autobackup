#!/bin/sh


: ${B2_ID:?"Missing B2 ID"}
: ${B2_KEY:?"Missing B2 key"}

TEST_BUCKET=duplicacy-autobackup-tests
BACKUP_LOCATION="b2://$TEST_BUCKET"
IMAGE_NAME=duplicacy-autobackup # local image
PASSPHRASE='correct horse battery staple'
BACKUP_NAME='test-backups'
data_dir=$(mktemp -d)

if [[ ! -z $(aws b2 ls $TEST_BUCKET) ]]; then
    echo "Test bucket is not empty. Exiting" >&2
    exit 1
fi

cleanup() {
    echo 'Cleaning up...'
    aws b2 rm b2://$TEST_BUCKET/ --recursive
    docker rm -f duplicacy-autobackup
    rm -f pre.sh
    rm -f post.sh
    rm -f $data_dir/post-script-executed
    rm -f $data_dir/pre-script-executed
}
trap cleanup EXIT

cat > $data_dir/hello.txt <<EOF
    hello, world!
EOF

cat > pre.sh <<EOF
    touch /data/pre-script-executed
EOF

cat > post.sh <<EOF
    touch /data/post-script-executed
EOF

docker run -d --name duplicacy-autobackup \
    -v $data_dir:/data \
    -v $(pwd)/pre.sh:/scripts/pre-backup.sh \
    -v $(pwd)/post.sh:/scripts/post-backup.sh \
    -e BACKUP_NAME=$BACKUP_NAME \
    -e BACKUP_LOCATION="$BACKUP_LOCATION" \
    -e BACKUP_SCHEDULE='0 2 * * *' \
    -e BACKUP_IMMEDIATELY='yes' \
    -e BACKUP_ENCRYPTION_KEY="$PASSPHRASE" \
    -e B2_ID=$B2_ID \
    -e B2_KEY=$B2_KEY \
    $IMAGE_NAME

echo "Waiting for backup to be performed..."
sleep 10

if [[ -z $(aws b2 ls $TEST_BUCKET) ]]; then
    echo "Nothing in test bucket. Exiting" >&2
    exit 2
fi

if [[ ! -d $data_dir/.duplicacy ]]; then
    echo "No duplicacy folder created. Exiting" >&2
    exit 3
fi

echo "Backup performed"

if [[ ! -f $data_dir/pre-script-executed ]]; then
    echo "Pre backup script wasn't executed" >&2
    exit 4
elif [[ ! -f $data_dir/post-script-executed ]]; then
    echo "Pre backup script wasn't executed" >&2
    exit 5
fi

echo "Pre and post backup script properly executed"
