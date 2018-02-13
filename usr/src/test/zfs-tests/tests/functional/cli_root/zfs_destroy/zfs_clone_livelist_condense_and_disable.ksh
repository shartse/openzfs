# !/bin/ksh
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright (c) 2018 by Delphix. All rights reserved.
#

# DESCRIPTION
# Verify zfs destroy test for clones with the livelist feature
# enabled.

# STRATEGY
# 1. Clone where livelist is condensed
#	- create clone, write several files, delete those files
#	- check that the number of livelist entries decreases
#	  after the delete
# 2. Clone where livelist is deactivated
#	- create clone, write files. Delete those files and the
#	  file in the filesystem when the snapshot was created
#	  so the clone and snapshot no longer share data
#	- check that the livelist is destroyed

. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/tests/functional/cli_root/zfs_destroy/zfs_destroy_common.kshlib

function cleanup
{
	log_must zfs destroy -Rf $TESTPOOL/$TESTFS1
	# reset the livelist sublist size to the original value
	mdb_ctf_set_int zfs_livelist_max_entries $ORIGINAL_MAX
	# reset the minimum percent shared to 75
	mdb_ctf_set_int zfs_livelist_min_percent_shared $ORIGINAL_MIN
}

function check_ll_len
{
    string="$(zdb -vvvvv $TESTPOOL | grep "Livelist")"
    substring="$1"
    msg=$2
    if test "${string#*$substring}" != "$string"; then
        return 0    # $substring is in $string
    else
	log_note $string
        log_fail "$msg" # $substring is not in $string
    fi
}

function test_condense
{
	# set the max livelist entries to a small value to more easily
	# trigger a condense
	mdb_ctf_set_int zfs_livelist_max_entries 0x14
	# set a small percent shared threshold so the livelist is not disabled
	mdb_ctf_set_int zfs_livelist_min_percent_shared 0xa
	clone_dataset $TESTFS1 snap $TESTCLONE
	# sync between each write to make sure a new entry is created
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE0
	log_must sync
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE1
	log_must sync
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE2
	log_must sync
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/testfile3
	log_must sync
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/testfile4
	log_must sync

	check_ll_len "5 entries" "Unexpected livelist size"

	# sync between each write to allow for a condense of the previous entry
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE0
	log_must sync
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE1
	log_must sync
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE2
	log_must sync
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/testfile3
	log_must sync
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/testfile4
	log_must sync

	check_ll_len "6 entries" "Condense did not occur"

	log_must zfs destroy $TESTPOOL/$TESTCLONE
	check_livelist_gone
}

function test_deactivated
{
	# Threshold set to 50 percent
	mdb_ctf_set_int zfs_livelist_min_percent_shared 0x32
	clone_dataset $TESTFS1 snap $TESTCLONE

	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE0
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE1
	sync
	# snapshot and clone share 'atestfile', 33 percent
	check_livelist_gone
	log_must zfs destroy -R $TESTPOOL/$TESTCLONE

	# Threshold set to 20 percent
	mdb_ctf_set_int zfs_livelist_min_percent_shared 0x14
	clone_dataset $TESTFS1 snap $TESTCLONE

	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE0
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE1
	log_must mkfile 5m /$TESTPOOL/$TESTCLONE/$TESTFILE2
	sync
	# snapshot and clone share 'atestfile', 25 percent
	check_livelist_exists $TESTCLONE
	log_must rm /$TESTPOOL/$TESTCLONE/atestfile
	# snapshot and clone share no files
	check_livelist_gone
	log_must zfs destroy -R $TESTPOOL/$TESTCLONE
}

ORIGINAL_MAX=$(mdb_get_hex zfs_livelist_max_entries)
ORIGINAL_MIN=$(mdb_get_hex zfs_livelist_min_percent_shared)

log_onexit cleanup
log_must zfs create $TESTPOOL/$TESTFS1
log_must mkfile 5m /$TESTPOOL/$TESTFS1/atestfile
log_must zfs snapshot $TESTPOOL/$TESTFS1@snap
test_condense
test_deactivated

log_pass "Clone's livelist condenses and disables as expected."
