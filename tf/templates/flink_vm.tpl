#cloud-config

datasource:
  ydb_path: ${ydb_path}
  api_key: ${api_key}  

runcmd:
  - sudo apt install -y openjdk-11-jre-headless
  - sudo apt install -y kafkacat 
  - snap install yq
  - echo 'export API_KEY=$(curl -sf -H Metadata-Flavor:Google 169.254.169.254/latest/user-data | yq -r .datasource.api_key)' >> /home/ubuntu/.bashrc
  - echo 'export DATABASE_PATH=$(curl -sf -H Metadata-Flavor:Google 169.254.169.254/latest/user-data | yq -r .datasource.ydb_path)' >> /home/ubuntu/.bashrc
  - sudo wget https://dlcdn.apache.org/flink/flink-1.19.0/flink-1.19.0-bin-scala_2.12.tgz -P /opt
  - sudo tar -xzf /opt/flink-1.19.0-bin-scala_2.12.tgz -C /opt
  - sudo rm /opt/flink-1.19.0-bin-scala_2.12.tgz
  - sudo chown ubuntu /opt/flink-1.19.0
  - wget https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.1.0-1.18/flink-sql-connector-kafka-3.1.0-1.18.jar -P /opt/flink-1.19.0/lib/
  - [ sed, -i, -e, 's/bind-address: localhost/bind-address: 0.0.0.0/g', /opt/flink-1.19.0/conf/config.yaml ]
### run flink after install
  - /opt/flink-1.19.0/bin/start-cluster.sh

bootcmd:
### or run it after reboot
  - test -f /opt/flink-1.19.0/bin/start-cluster.sh && /opt/flink-1.19.0/bin/start-cluster.sh
