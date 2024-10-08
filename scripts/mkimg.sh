#! /bin/sh

# Recreate the golden image used for the integration tests

# UFS has many options that affect on-disk format.  Initially this project will
# only support the most common options, but more may be added later.  See
# newfs(8) for the full list.

# The golden image should be as small as possible while still achieving good
# coverage, so as to minimize the size of data stored in git.

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# $1: mountpoint
populate() {
    cd "$1" || die "failed to cd into '$1'"

    echo 'This is a simple file.' > file1
    mkdir -p dir1/dir2/dir3
    echo 'Hello World' > dir1/dir2/dir3/file2
    jot $((1 << 16)) 0 | xargs printf '%015x\n' > file3
    ln -sf dir1/dir2/dir3/file2 link1
    ln -sf "$(yes ./ | head -n508 | tr -d '\n')//file1" long-link
    tr '\0' 'x' < /dev/zero | dd of=sparse bs=4096 seek=$(((12 + 4096) * 8)) count=8
    tr '\0' 'x' < /dev/zero | dd of=sparse2 bs=4096 seek=$(((12 + 4096) * 8)) count=1
    tr '\0' 'x' < /dev/zero | dd of=sparse3 bs=4096 seek=$(((12 + 4096 + 4096 * 4096) * 8)) count=8
    touch xattrs
    setextattr user test testvalue xattrs
    touch xattrs2
    # 2297 is the maximum number of xattrs that fit in this case
    jot 2297 | xargs -I{} setextattr user 'attr{}' 'value{}' xattrs2
    touch xattrs3
    # 4096 would be too much
    setextattr user 'big' "$(jot 4000 0 | xargs printf '%015x\n')" xattrs3

    cd - || die "failed to cd back"
}

# $1: name
# $2: size
# $@: args to newfs
create() {
    name=$1
    path=resources/${name}.img
    size=$2
    shift 2
    
    truncate -s "$size" "$path" || die "$path: failed to allocate $size"
    dev=$(mdconfig -a -t vnode -f "$path") || die "$path: failed to create virtual device"
    newfs "$@" "$dev" || die "$path: failed to newfs $dev"

    mnt=$(mktemp -d) || die "$path: failed to create tempdir"
    mount -t ufs "/dev/$dev" "$mnt" || die "$path: failed to mount '/dev/$dev' onto '$mnt'"

    populate "$mnt"

    # These may fail with only a warning:
    umount "$mnt"
    rmdir "$mnt"
    mdconfig -d -u "$dev"

    zstd -f "$path" || die "$path: failed to compress with zstd"
}

# I don't know why it works, but it does. Tested on FreeBSD/powerpc64, OpenBSD/amd64, Arch Linux (amd64)
case "$(echo I | tr -d '[:space:]' | od -to2 | awk 'NR==1 {print substr($2, 6, 1)}')" in
    0)
	ENDIAN=big
	;;
    1)
	ENDIAN=little
	;;
    *)
	die "cannot determine endianness of system"
	;;
esac

args=$(getopt 'p:s:' $*) || die "usage: ./scripts/mkimg.sh [-p dir|-s size]"
set -- $args

SIZE=4m

while true; do
    case "$1" in
	-p)
	    populate "$2"
	    exit 0
	    ;;
	-s)
	    SIZE=$2
	    shift 2
	    ;;
	--)
	    shift
	    break
	    ;;
    esac
done

create "ufs-${ENDIAN}" "${SIZE}"
