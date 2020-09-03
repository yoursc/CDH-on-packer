#/bin/bash -e

MODE=$1
WORKDIR=$(cd $(dirname $0) && pwd )
MYSQL_PASSWD='Yous1!&<2*34Qv,<qtyafc>><><*'

URL_REPO=https://venen-repos.oss-cn-zhangjiakou-internal.aliyuncs.com

URL_CLOUDERA=${URL_REPO}/cloudera
#URL_CLOUDERA=https://archive.cloudera.com

# Parcels
PARCELS_NAME=CDH-6.2.0-1.cdh6.2.0.p0.967373-el7.parcel
URL_PARCELS=${URL_CLOUDERA}/cdh6/6.2.0/parcels/${PARCELS_NAME}
MANIFEST_PATH=${URL_CLOUDERA}/cdh6/6.2.0/parcels/manifest.json
PATH_PARCEL=/data/http/cdh6/6.2.0/parcel

# Cloudera-Manage
FILE_CM=cm6.2.0-redhat7.tar.gz
URL_CM=${URL_CLOUDERA}/cm6/6.2.0/repo-as-tarball/${FILE_CM}
PATH_CM=/data/http/cm6

# Other-Soft
FILE_CONDA=Miniconda2-4.7.12-Linux-x86_64.sh
URL_CONDA=${URL_REPO}/anaconda/miniconda/${FILE_CONDA}
PATH_SOFT=/data/download

# Conda install path
CONDA_INSTALL=/data/miniconda2

mkdir -p /data/http

SetSystem(){
    # disable ipv6
    echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf
    sysctl -p /etc/sysctl.conf
    # disable big-page
    echo 'echo never > /sys/kernel/mm/transparent_hugepage/defrag' >> /etc/rc.d/boot.local
    echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.d/boot.local
}

InstallCdhNode(){
    wget -c ${URL_CM} -P ${PATH_CM}/
    wget -c ${URL_CM}.sha256 -P ${PATH_CM}/
    wget -c ${URL_CONDA} -P ${PATH_SOFT}/

    echo `cat ${PATH_CM}/${FILE_CM}.sha256`
    sha256sum ${PATH_CM}/${FILE_CM}
    sleep 5
    # todo 判断检验结果
    tar -zxvf ${PATH_CM}/${FILE_CM} -C ${PATH_CM}
    #### INSTALL ####
    # conda
    bash ${PATH_SOFT}/${FILE_CONDA} -b -p ${CONDA_INSTALL}
    ${CONDA_INSTALL}/bin/conda init
    source ~/.bashrc
    pip install psycopg2-binary
    # base
    yum -y install httpd yum-utils
    # krb
    yum -y install krb5-libs krb5-workstation
    # depend for cdh-agent
    yum -y install GeoIP MySQL-python bind-libs bind-libs-lite bind-license bind-utils cyrus-sasl-gssapi cyrus-sasl-plain fuse fuse-libs geoipupdate keyutils-libs-devel krb5-devel libcom_err-devel libkadm5 libselinux-devel libsepol-devel libverto-devel mod_ssl openssl-devel pcre-devel postgresql-libs python-psycopg2 rpcbind zlib-devel
    # mysql
    wget -c https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm -P ${PATH_SOFT}/
    rpm -Uvh ${PATH_SOFT}/mysql80-community-release-el7-3.noarch.rpm
    yum-config-manager --disable mysql80-community
    yum-config-manager --enable mysql57-community
    yum repolist
    yum -y install mysql-connector-java
    # cdh
    rpm -Uvh ${PATH_CM}/cm6.2.0/RPMS/x86_64/oracle-j2sdk1.8-1.8.0+update181-1.x86_64.rpm
    rpm -Uvh ${PATH_CM}/cm6.2.0/RPMS/x86_64/cloudera-manager-daemons-6.2.0-968826.el7.x86_64.rpm
    rpm -Uvh ${PATH_CM}/cm6.2.0/RPMS/x86_64/cloudera-manager-agent-6.2.0-968826.el7.x86_64.rpm
    #### CONFIG ####
    # agent
    cp /etc/cloudera-scm-agent/config.ini /etc/cloudera-scm-agent/config.ini.bak
    sed -i 's/server_host=localhost/server_host=cdh-cm/g' /etc/cloudera-scm-agent/config.ini
    systemctl enable cloudera-scm-agent
    # kerberos
    mv /etc/krb5.conf /etc/krb5.conf.bak
    cp ${WORKDIR}/krb5.conf /etc/krb5.conf
}


InstallCdhManager(){
    #### DOWNLOAD ####
    wget -c ${URL_PARCELS} -P ${PATH_PARCEL}/
    wget -c ${URL_PARCELS}.sha256 -P ${PATH_PARCEL}/
    wget -c ${MANIFEST_PATH} -P ${PATH_PARCEL}/

    echo `cat ${PATH_PARCEL}/${PARCELS_NAME}.sha256`
    sha256sum ${PATH_PARCEL}/${PARCELS_NAME}
    # todo 判断检验结果
    sleep 5s

    #### INSTALL ####
    yum -y install krb5-server krb5-auth-dialog openldap-clients
    yum -y install mysql-community-server
    rpm -Uvh  ${PATH_CM}/cm6.2.0/RPMS/x86_64/cloudera-manager-server-6.2.0-968826.el7.x86_64.rpm

    #### CONFIG ####
    # mysql
    systemctl restart mysqld
    MYSQL_INIT_PASSWD=`grep 'temporary password' /var/log/mysqld.log | awk -F 'root@localhost: ' '{print $2}'`
    mv /etc/my.cnf /etc/my.cnf.bak
    cp ${WORKDIR}/my.cnf /etc/my.cnf
    mysql --user=root --password=${MYSQL_INIT_PASSWD} --connect-expired-password --execute="ALTER USER root@localhost identified by '${MYSQL_PASSWD}';"
    mysql --user=root --password=${MYSQL_PASSWD} --execute='uninstall plugin validate_password;'
    systemctl restart mysqld
    systemctl enable mysqld
    mysql --user=root --password=${MYSQL_PASSWD} --execute="source ${WORKDIR}/mysql_init.sql"
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql scm scm scm
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql amon amon amon
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql rman rman rman
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql hue hue hue
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql metastore hive hive
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql sentry sentry sentry
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql nav nav nav
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql navms navms navms
    /opt/cloudera/cm/schema/scm_prepare_database.sh mysql oozie oozie oozie
    # http
    mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.bak
    cp ${WORKDIR}/httpd.conf /etc/httpd/conf/httpd.conf
    systemctl start httpd
    systemctl enable httpd
    # cloudera-scm
    mv /etc/cloudera-scm-server/db.properties /etc/cloudera-scm-server/db.properties.bak
    cp ${WORKDIR}/db.properties /etc/cloudera-scm-server/db.properties
    systemctl enable cloudera-scm-server
    # Krb
    mv /var/kerberos/krb5kdc/kdc.conf /var/kerberos/krb5kdc/kdc.conf.bak
    cp ${WORKDIR}/kdc.conf /var/kerberos/krb5kdc/kdc.conf
    mv /var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl.bak
    cp ${WORKDIR}/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl
    systemctl enable krb5kdc
    systemctl enable kadmin
    # todo 创建一个软连接，将HOSTS文件链接到HTTP文件服务器以供其他节点下载
}

InitKDC(){

kdb5_util create -r CDH.COM -s<<EOF
admin
admin
<<EOF

kadmin.local<<EOF
addprinc admin/admin@CDH.COM
admin
admin
exit
<<EOF

}


################################
#                              #
#            主程序            #
#                              #
################################

SetSystem
InstallCdhNode
if [ "$MODE" = "CM" ]
then
    InstallCdhManager
fi

#### CLEAR ####
rm -f ${PATH_SOFT}/mysql80-community-release-el7-3.noarch.rpm
rm -rf ${PATH_CM}
