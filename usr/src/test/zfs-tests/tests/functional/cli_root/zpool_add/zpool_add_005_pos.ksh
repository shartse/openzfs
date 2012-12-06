#!/bin/ksh -p
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright 2009 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#
. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/tests/functional/cli_root/zpool_add/zpool_add.kshlib

#
# DESCRIPTION:
#       'zpool add' should return fail if
#	1. vdev is part of an active pool
#	2. vdev is currently mounted
#	3. vdev is in /etc/vfstab
#	3. vdev is specified as the dedicated dump device
#
# STRATEGY:
#	1. Create case scenarios
#	2. For each scenario, try to add the device to the pool
#	3. Verify the add operation get failed
#

verify_runnable "global"

function cleanup
{
	poolexists "$TESTPOOL" && \
		destroy_pool "$TESTPOOL"
	poolexists "$TESTPOOL1" && \
		destroy_pool "$TESTPOOL1"

	if [[ -n $saved_dump_dev ]]; then
		log_must eval "$DUMPADM -u -d $saved_dump_dev > /dev/null"
	fi

	partition_cleanup
}

log_assert "'zpool add' should fail with inapplicable scenarios."

log_onexit cleanup

mnttab_dev=$(find_mnttab_dev)
vfstab_dev=$(find_vfstab_dev)
saved_dump_dev=$(save_dump_dev)
dump_dev=${disk}s${SLICE3}

create_pool "$TESTPOOL" "${disk}s${SLICE0}"
log_must poolexists "$TESTPOOL"

create_pool "$TESTPOOL1" "${disk}s${SLICE1}"
log_must poolexists "$TESTPOOL1"
log_mustnot $ZPOOL add -f "$TESTPOOL" ${disk}s${SLICE1}

log_mustnot $ZPOOL add -f "$TESTPOOL" $mnttab_dev

log_mustnot $ZPOOL add -f "$TESTPOOL" $vfstab_dev

log_must $ECHO "y" | $NEWFS /dev/dsk/$dump_dev > /dev/null 2>&1
log_must $DUMPADM -u -d /dev/dsk/$dump_dev > /dev/null
log_mustnot $ZPOOL add -f "$TESTPOOL" $dump_dev

log_pass "'zpool add' should fail with inapplicable scenarios."
