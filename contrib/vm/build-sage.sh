#!/bin/sh

VM=sagecell
./start $VM

# vmm is:
# Host vmm
#    User root
#    HostName localhost
#    Port 5457
#    NoHostAuthenticationForLocalhost yes


VMSSH=vmm
### The Sage version
SOURCE=$1
if [ -z $SOURCE ] || [ ! -f $SOURCE ] ; then
    echo "Cannot find Sage source archive $SOURCE."
    exit 1
fi

echo 'Syncing sage source'
rsync -avv -e ssh $SOURCE $VMSSH:/home/sage-source.tar

#scp "$SCRIPTSDIR"/systemd-run-sage.service $VMSSH:/lib/systemd/system/sage@.service

#scp "$SCRIPTSDIR"/sage-bash-profile $VMSSH:/home/sage/.bash_profile

ssh $VMSSH -T <<EOF | tee  install.log
  set -v
  echo 'Updating system'
  yum -y update
  yum clean all

  echo 'Resetting accounts'
  /usr/sbin/userdel -r sagecell
  /usr/sbin/userdel -r sageworker
  /usr/sbin/useradd sagecell
  /usr/sbin/useradd sageworker

  echo 'Setting up ssh keys'
  su -l sagecell -c 'ssh-keygen -q -N "" -f /home/sagecell/.ssh/id_rsa'
  su -l sageworker -c 'mkdir .ssh && chmod 700 .ssh'
  cp -r /home/sagecell/.ssh/id_rsa.pub /home/sageworker/.ssh/authorized_keys
  chown -R sageworker.sageworker /home/sageworker/
  restorecon -R /home/sagecell/.ssh
  restorecon -R /home/sageworker/.ssh

  #cd /etc/systemd/system/getty.target.wants
  #ln -sf /lib/systemd/system/sage@.service getty@tty8.service


  echo 'Extracting sage'
  su -l sagecell
  #set -v
  tar xf /home/sage-source.tar
  rm sage
  ln -s sage* sage
  cd sage

  echo 'Compiling Sage'
  # export SAGE_ATLAS_ARCH=fast
  export SAGE_ATLAS_LIB=/usr/lib64/atlas/
  #export SAGE_FAT_BINARY="yes"
  export MAKE='make -j16'
  make
  #make test
  ./sage <<EOFSAGE
     quit
EOFSAGE

  echo 'Setting up temporary directory'
  

  echo 'Installing sagecell'
  rm -rf local/lib/python/site-packages/[iI]Python*
  ./sage -sh -c "easy_install https://github.com/ipython/ipython/archive/0d4706f.zip"
  ./sage -i http://sage.math.washington.edu/home/jason/sagecell-spkg/sagecell-2013-05-20.spkg
EOF

scp config.py $VMSSH:/home/sagecell/sage/devel/sagecell/config.py

RC=`grep "Error building Sage" install.log` 
if [ "$RC" != "" ]; then
   echo "Error building Sage!"
   #VBoxManage unregistervm $UUID --delete
   exit 1
fi

ssh $VMSSH <<EOF
  # get the localhost in the known_hosts file
  su -l sagecell -c 'ssh -oStrictHostKeyChecking=no sageworker@localhost echo hi'
  # make sure the config file is owned by the right person
  chown -R sagecell.sagecell /home/sagecell/sage/devel/sagecell/config.py
EOF

# don't shut down; just exit
exit

ssh $VMSSH -T <<EOF
  #dd if=/dev/zero of=/zerofile ; rm -f /zerofile
  #shutdown -h now
EOF


echo "Waiting for the guest addition installation to finish..."
STATUS=`virsh dominfo $VM | grep 'State:.*running'`
while [ "$STATUS" != "" ]; do
    date
    sleep 10
    STATUS=`virsh dominfo $VM | grep 'State:.*running'`
done
#if [ $? -ne 0 ]; then
#   echo "Failed to wait for installation to finish!"
#   exit 1
#fi
