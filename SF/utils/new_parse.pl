#!/usr/bin/perl
#
# $Id$
#
# new_parse.pl - new script to parse out the database dumps and create/update/delete user
#		 accounts on the client machines
use Sys::Hostname;
#
# added by LJ
use Carp;

$hostname = hostname();


# Make sure umask is properly positioned for the
# entire session. Root has umask 022 by default
# causing all the mkdir xxx, 775 to actually 
# create dir with permission 755 !!
# So set umask to 002 for the entire script session 
umask 002;

require("include.pl");  # Include all the predefined functions and variables

my $user_file = $file_dir . "user_dump";
my $group_file = $file_dir . "group_dump";
my ($uid, $status, $username, $shell, $passwd, $realname);
my ($gname, $gstatus, $gid, $userlist);

# Open up all the files that we need.
@userdump_array = open_array_file($user_file);
@groupdump_array = open_array_file($group_file);
@passwd_array = open_array_file("/etc/passwd");
@shadow_array = open_array_file("/etc/shadow");
@group_array = open_array_file("/etc/group");

#LJ The file containing all allowed root for CVS server
#
my $cvs_root_allow_file = "/etc/cvs_root_allow";
@cvs_root_allow_array = open_array_file($cvs_root_allow_file);

#
# Loop through @userdump_array and deal w/ users.
#
print ("\n\n	Processing Users\n\n");
while ($ln = pop(@userdump_array)) {
	chop($ln);
	($uid, $status, $username, $shell, $passwd, $realname) = split(":", $ln);

# LJ commented out because it's all on the same machine for the moment
# The SF site has  a cvs server which names start with cvs. We don't
#
#	if (substr($hostname,0,3) eq "cvs") {
#		$shell = "/bin/cvssh";
#	}
	
	$uid += $uid_add;

	$username =~ tr/A-Z/a-z/;
	
	$user_exists = getpwnam($username);
	
	if ($status eq 'A' && $user_exists) {
		update_user($uid, $username, $realname, $shell, $passwd);
	
	} elsif ($status eq 'A' && !$user_exists) {
		add_user($uid, $username, $realname, $shell, $passwd);
	
	} elsif ($status eq 'D' && $user_exists) {
		delete_user($username);
	
	} elsif ($status eq 'D' && !$user_exists) {
		print("Error trying to delete user: $username\n");
		
	} elsif ($status eq 'S' && $user_exists) {
		suspend_user($username);
		
	} elsif ($status eq 'S' && !$user_exists) {
		print("Error trying to suspend user: $username\n");
		
	} else {
		print("Unknown Status Flag: $username\n");
	}
}

#
# Loop through @groupdump_array and deal w/ users.
#
print ("\n\n	Processing Groups\n\n");
while ($ln = pop(@groupdump_array)) {
	chop($ln);
	($gname, $gstatus, $gid, $userlist) = split(":", $ln);
	
	$cvs_id = $gid + 50000;
	$gid += $gid_add;
	$userlist =~ tr/A-Z/a-z/;

	$group_exists = getgrnam($gname);

	my $group_modified = 0;
	if ($gstatus eq 'A' && $group_exists) {
	        $group_modified = update_group($gid, $gname, $userlist);
	
	} elsif ($gstatus eq 'A' && !$group_exists) {
		add_group($gid, $gname, $userlist);
		
	} elsif ($gstatus eq 'D' && $group_exists) {
		delete_group($gname);

	} elsif ($gstatus eq 'D' && !$group_exists) {
# LJ Why print an error here ? The delete user function leave the D flag in place
# LJ so this error msg always appear when a project has been deleted
#		print("Error trying to delete group: $gname\n");
	  print("Deleted Group: $gname\n");
	}

# LJ Do not test if we are on the CVS machine. It's all on atlas
#	if ((substr($hostname,0,3) eq "cvs") && $gstatus eq 'A' && !(-e "$cvs_prefix/$gname")) {
	if ( $gstatus eq 'A' && !(-e "$cvs_prefix/$gname")) {
		print("Creating a CVS Repository for: $gname\n");
		# Let's create a CVS repository for this group
		$cvs_dir = "$cvs_prefix/$gname";

		# Firce create the repository
		mkdir $cvs_dir, 0775;
		system("/usr/bin/cvs -d$cvs_dir init");
	
		# turn off pserver writers, on anonymous readers
		# LJ - See CVS writers update below. Just create an
		# empty writers file so that we can set up the appropriate
		# ownership right below. We will put names in writers
		# later in the script
		system("echo \"\" > $cvs_dir/CVSROOT/writers");
		$group_modified = 1;

		# LJ - we no longer allow anonymous access by default
		#system("echo \"anonymous\" > $cvs_dir/CVSROOT/readers");
		#system("echo \"anonymous:\\\$1\\\$0H\\\$2/LSjjwDfsSA0gaDYY5Df/:anoncvs_$gname\" > $cvs_dir/CVSROOT/passwd");

		# LJ But to allow checkout/update to registered users we
		# need to setup a world writable directory for CVS lock files
		mkdir "$cvs_dir/.lockdir", 0777;
		chmod 0777, "$cvs_dir/.lockdir"; # overwrite umask value
		system("echo  >> $cvs_dir/CVSROOT/config");
		system("echo '# !!! CodeX Specific !!! DO NOT REMOVE' >> $cvs_dir/CVSROOT/config");
		system("echo '# Put all CVS lock files in a single directory world writable' >> $cvs_dir/CVSROOT/config");
		system("echo '# directory so that any CodeX registered user can checkout/update' >> $cvs_dir/CVSROOT/config");
		system("echo '# without having write permission on the entire cvs tree.' >> $cvs_dir/CVSROOT/config");
		system("echo 'LockDir=$cvs_dir/.lockdir' >> $cvs_dir/CVSROOT/config");

		# setup loginfo to make group ownership every commit
		system("echo \"ALL (cat;chgrp -R $gname $cvs_dir)>/dev/null 2>&1\" > $cvs_dir/CVSROOT/loginfo");
		system("echo \"\" > $cvs_dir/CVSROOT/val-tags");
		chmod 0664, "$cvs_dir/CVSROOT/val-tags";

		# set group ownership, anonymous group user
		system("chown -R nobody:$gid $cvs_dir");
		system("chmod g+rw $cvs_dir");

		# And finally add a user for this repository
		push @passwd_array, "anoncvs_$gname:x:$cvs_id:$gid:Anonymous CVS User for $gname:$cvs_prefix/$gname:/bin/false\n";
	}

	# LJ if the CVS repo has just been created or the user list
	# in the group has been modified then update the CVS
	# writer file

	if ($group_modified) {
	  # LJ On atlas writers go through pserver as well so put
	  # group members in writers file. Do not write anything
	  # in the CVS passwd file. The pserver protocol will fallback
	  # on /etc/passwd for user authentication
	  my $cvswriters_file = "$cvs_prefix/$gname/CVSROOT/writers";
	  open(WRITERS,"+>$cvswriters_file")
	    or croak "Can't open CVS writers file $cvswriters_file: $!";  
	  print WRITERS join("\n",split(",",$userlist)),"\n";
	  close(WRITERS);
	}
}

#
# Now write out the new files
#
write_array_file("/etc/passwd", @passwd_array);
write_array_file("/etc/shadow", @shadow_array);
write_array_file("/etc/group", @group_array);

# LJ and write the CVS root file
write_array_file($cvs_root_allow_file, @cvs_root_allow_array);


###############################################
# Begin functions
###############################################

#############################
# User Add Function
#############################
sub add_user {  
	my ($uid, $username, $realname, $shell, $passwd) = @_;
	my $skel_array = ();
	
	$home_dir = $homedir_prefix.$username;

	print("Making a User Account for : $username\n");
		
	push @passwd_array, "$username:x:$uid:$uid:$realname:$home_dir:$shell\n";
	push @shadow_array, "$username:$passwd:$date:0:99999:7:::\n";
	push @group_array, "$username:x:$uid:\n";

	# LJ Couple of modifications here
	# Now lets create the homedir and copy the contents of
	# /etc/skel_codex into it. The change the ownership
	mkdir $home_dir, 0751;
	system("cd /etc/skel_codex; tar cf - . | (cd  $home_dir ; tar xf - )");	
#	chown $uid, $uid, $home_dir;
	system("chown -R $uid.$uid $home_dir");
}

#############################
# User Add Function
#############################
sub update_user {
	my ($uid, $username, $realname, $shell, $passwd) = @_;
	my ($p_username, $p_junk, $p_uid, $p_gid, $p_realname, $p_homedir, $p_shell);
	my ($s_username, $s_passwd, $s_date, $s_min, $s_max, $s_inact, $s_expire, $s_flag, $s_resv, $counter);
	
	print("Updating Account for: $username\n");
	
	foreach (@passwd_array) {
		($p_username, $p_junk, $p_uid, $p_gid, $p_realname, $p_homedir, $p_shell) = split(":", $_);
		
		if ($uid == $p_uid) {
			if ($realname ne $p_realname) {
				$passwd_array[$counter] = "$username:x:$uid:$uid:$realname:$p_homedir:$shell\n";
			} elsif ($shell ne $t_shell) {
				$passwd_array[$counter] = "$username:x:$uid:$uid:$p_realname:$p_homedir:$p_shell";
			}
		}
		$counter++;
	}
	
	$counter = 0;
	
	foreach (@shadow_array) {
		($s_username, $s_passwd, $s_date, $s_min, $s_max, $s_inact, $s_expire, $s_flag, $s_resv) = split(":", $_);
		if ($username eq $s_username) {
			if ($passwd ne $s_passwd) {
				$shadow_array[$counter] = "$username:$passwd:$s_date:$s_min:$s_max:$s_inact:$s_expire:$s_flag:$s_resv";
			}
		}
		$counter++;
	}
}

#############################
# User Deletion Function
#############################
sub delete_user {
	my ($username, $junk, $uid, $gid, $realname, $homedir, $shell, $counter);
	my $this_user = shift(@_);
	
	foreach (@passwd_array) {
		($username, $junk, $uid, $gid, $realname, $homedir, $shell) = split(":", $_);
		if ($this_user eq $username) {
			$passwd_array[$counter] = '';
		}
		$counter++;
	}
	
	print("Deleting User : $this_user\n");
	system("cd $homedir_prefix ; /bin/tar -czf $tar_dir/$username.tar.gz $username");
	system("rm -fr $homedir_prefix/$username");
}

#############################
# User Suspension Function
#############################
sub suspend_user {
	my $this_user = shift(@_);
	my ($s_username, $s_passwd, $s_date, $s_min, $s_max, $s_inact, $s_expire, $s_flag, $s_resv, $counter);
	
	my $new_pass = "!!" . $s_passwd;
	
	foreach (@shadow_array) {
		($s_username, $s_passwd, $s_date, $s_min, $s_max, $s_inact, $s_expire, $s_flag, $s_resv) = split(":", $_);
		if ($username eq $s_username) {
		       $shadow_array[$counter] = "$s_username:$new_pass:$s_date:$s_min:$s_max:$s_inact:$s_expire:$s_flag:$s_resv";
		}
		$counter++;
	}
}


#############################
# Group Add Function
#############################
sub add_group {  
	my ($gid, $gname, $userlist) = @_;
	my ($log_dir, $cgi_dir, $ht_dir, $cvs_dir, $cvs_id);
	
	$group_dir = $grpdir_prefix.$gname;
	$log_dir = $group_dir."/log";
	$cgi_dir = $group_dir."/cgi-bin";
	$ht_dir = $group_dir."/htdocs";
	$ftp_frs_group_dir = $ftp_frs_dir_prefix.$gname;
	$ftp_anon_group_dir = $ftp_anon_dir_prefix.$gname;

	print("Making a Group for : $gname\n");
		
	push @group_array, "$gname:x:$gid:$userlist\n";

# LJ Add the CVS repo in the allowed root for CVS server
	push @cvs_root_allow_array, "$cvs_prefix/$gname\n";
	
# LJ Comment the if. Does not apply on CodeX
#	if (substr($hostname,0,3) ne "cvs") {

		# Now lets create the group's homedir.
		mkdir $group_dir, 0775;
		mkdir $log_dir, 0775;
		mkdir $cgi_dir, 0775;
		mkdir $ht_dir, 0775;
		chown $dummy_uid, $gid, ($group_dir, $log_dir, $cgi_dir, $ht_dir);
		# Added by LJ - Copy the default empty page for Web site
		system("cp default_page.php $ht_dir/index.php");
		chown $dummy_uid, $gid, "$ht_dir/index.php";
		chmod 0664, "$ht_dir/index.php";       

		# Now lets create the group's ftp homedir for anonymous ftp space
   	        # (this one must be owned by the project gid so that all project
                # admins can work on it (upload, delete, etc...)
		mkdir $ftp_anon_group_dir, 0775;
		chown $dummy_uid, $gid, "$ftp_anon_group_dir";   

		# Now lets create the group's ftp homedir for file release space
   	        # (this one has limited write access to project members and read
	        # read is also for project members as well (download has to go
	        # through the Web for accounting and traceability purpose)
		mkdir $ftp_frs_group_dir, 0771;
		chown $dummy_uid, $gid, "$ftp_frs_group_dir";   
		
#	 }

}

#############################
# Group Update Function
#############################
sub update_group {
	my ($gid, $gname, $userlist) = @_;
	my ($p_gname, $p_junk, $p_gid, $p_userlist, $counter);
# LJ modification to return TRUE if user list has changed
	my $modified = 0;
	
	print("Updating Group: $gname\n");
	
	foreach (@group_array) {
		($p_gname, $p_junk, $p_gid, $p_userlist) = split(":", $_);
		
		if ($gid == $p_gid) {
			if ($userlist ne $p_userlist) {
				$group_array[$counter] = "$gname:x:$gid:$userlist\n";
				$modified = 1;
			}
		}
		$counter++;
	}

	return $modified;
}

#############################
# Group Delete Function
#############################
sub delete_group {
	my ($gname, $x, $gid, $userlist, $counter);
	my $this_group = shift(@_);
	$counter = 0;
	
	foreach (@group_array) {
		($gname, $x, $gid, $userlist) = split(":", $_);
		if ($this_group eq $gname) {
			$group_array[$counter] = '';
		}
		$counter++;
	}

	# LJ delete CVS repository from the list of CVS allowed root
	$counter = 0;
	foreach (@cvs_root_allow_array) {
	  if ( $cvs_root_allow_array[$counter] eq "$cvs_prefix/$gname") {
	    $cvs_root_allow_array[$counter] = '';
	  }
	  $counter++;
	}

# LJ Comment. Useless on CodeX
#	if (substr($hostname,0,3) ne "cvs") {
		print("Deleting Group: $this_group\n");
		system("cd $grpdir_prefix ; /bin/tar -czf $tar_dir/$this_group.tar.gz $this_group");
		system("rm -fr $grpdir_prefix/$this_group");

# LJ And do the same for the CVS directory
		system("cd $cvs_prefix ; /bin/tar -czf $tar_dir/$this_group-cvs.tar.gz $this_group");
		system("rm -fr $cvs_prefix/$this_group");


#	}
}

