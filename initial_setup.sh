# NetworkManagerを停止
systemctl stop NetworkManager
systemctl disable NetworkManager
systemctl disable firewalld
systemctl stop firewalld
/sbin/chkconfig network on


# IPアドレスを固定（インターフェース名は環境によって読み替える。IPアドレスを買える場合も以降の手順を読み替える。
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-enp0s3
DEVICE="enp0s3"
TYPE="Ethernet"
BOOTPROT="static"
ONBOOT="yes"
IPADDR=192.168.99.199
NETMASK=255.255.255.0
EOF

# リブートしてネットワークが接続できるか確認。
reboot


# 最新化、必要パッケージの導入
yum update -y
yum install -y centos-release-openstack-newton
yum install -y openstack-packstack openstack-utils crudini
reboot


# インストーラーを起動する際のLANGを設定
LANG=en_US.utf-8
LC_ALL=en_US.utf-8


# インストーラーの設定ファイル（answer.txt）を生成
packstack --dry-run --allinone --default-password='password' --provision-demo=n --os-neutron-ovs-bridge-mappings=extnet:br-ex --os-neutron-ml2-type-drivers=vxlan,flat --gen-answer-file=/root/answer.txt


# 設定ファイルの編集（各サービスが起動するIPアドレスを設定）
for i in config_controller_host config_compute_hosts config_network_hosts config_storage_host config_sahara_host config_amqp_host config_mariadb_host config_mongodb_host config_redis_host
do
crudini --set /root/answer.txt general $i 192.168.99.199
done


# 設定ファイルの編集（インストールするサービスを設定）
for i in config_mariadb_install config_glance_install config_cinder_install config_nova_install config_neutron_install config_horizon_install config_swift_install config_heat_install config_client_install config_lbaas_install
do
crudini --set /root/answer.txt general $i y
done


# 設定ファイルの編集（インストールしないサービスを設定）
for i in config_manila_install config_ceilometer_install config_aodh_install config_gnocchi_install config_sahara_install config_trove_install config_ironic_install config_nagios_install config_neutron_metering_agent_install config_heat_cloudwatch_install config_heat_cfn_install
do
crudini --set /root/answer.txt general $i n
done


# 設定ファイルの編集（その他）
crudini --set /root/answer.txt general CONFIG_KEYSTONE_REGION                  RegionOne
crudini --set /root/answer.txt general CONFIG_CINDER_VOLUMES_SIZE              20G
crudini --set /root/answer.txt general CONFIG_SWIFT_STORAGE_SIZE               10G
crudini --set /root/answer.txt general CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES vxlan
crudini --set /root/answer.txt general CONFIG_NEUTRON_OVS_TUNNEL_IF            enp0s3


# インストールの実行
packstack --answer-file=/root/answer.txt


# インストール後の設定
openstack-config --set /etc/nova/nova.conf DEFAULT api_rate_limit false
openstack-config --set /etc/nova/nova.conf DEFAULT novncproxy_host 0.0.0.0
openstack-config --set /etc/nova/nova.conf DEFAULT novncproxy_port 6080

openstack-config --set /etc/nova/nova.conf vnc enabled true
openstack-config --set /etc/nova/nova.conf vnc novncproxy_base_url http://192.168.99.199:6080/vnc_auto.html
openstack-config --set /etc/nova/nova.conf vnc vncserver_listen 0.0.0.0
openstack-config --set /etc/nova/nova.conf vnc vncserver_proxyclient_address 192.168.99.199
openstack-config --set /etc/nova/nova.conf vnc vnc_keymap ja

openstack-config --set /etc/nova/nova.conf libvirt virt_type qemu

openstack-config --set /etc/nova/nova.conf DEFAULT cpu_allocation_ratio 32
openstack-config --set /etc/nova/nova.conf DEFAULT ram_allocation_ratio 5
openstack-config --set /etc/nova/nova.conf DEFAULT disk_allocation_ratio 3
openstack-config --set /etc/nova/nova.conf DEFAULT allow_resize_to_same_host true
openstack-config --set /etc/cinder/cinder.conf lvm volume_clear     none
openstack-config --set /etc/neutron/plugin.ini ml2_type_vxlan vni_ranges 10:1000



# ブリッジの設定
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-enp0s8
DEVICE="enp0s8"
BOOTPROT="none"
ONBOOT="yes"
TYPE="OVSPort"
DEVICETYPE="ovs"
OVS_BRIDGE="br-ex"
EOF

cat << EOF > /etc/sysconfig/network-scripts/ifcfg-br-ex
DEVICE="br-ex"
BOOTPROT="none"
ONBOOT="yes"
TYPE="OVSBridge"
DEVICETYPE="ovs"
OVSBOOTPROTO="none"
OVSDHCPINTERFACES="enp0s8"
EOF


# 再起動
reboot


# 動作確認
source ~/keystone_admin
openstack compute service list
openstack orchestration service list
openstack volume service list
openstack network agent list


# Publicネットワークの作成
FIP_START=192.168.99.200
FIP_END=192.168.99.230
FIP_CIDR=192.168.99.0/24
EXT_GW=192.168.99.199

neutron net-create public --router:external=True --provider:network_type flat --provider:physical_network extnet
neutron subnet-create --name public-subnet \
--allocation-pool start=${FIP_START},end=${FIP_END} \
--disable-dhcp \
--no-gateway  \
public ${FIP_CIDR}


# テストイメージの導入
wget http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
openstack image create --disk-format qcow2 --public --file cirros-0.3.5-x86_64-disk.img cirros-0.3.5

# 一般ユーザーの作成
openstack role create handson
openstack project create project01
openstack user create --project project01 --password 'openstack' openstack

openstack role add --user openstack --project project01 handson
openstack role add --user openstack --project project01 SwiftOperator
openstack role add --user openstack --project project01 heat_stack_owner

