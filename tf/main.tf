### network ###
resource "yandex_vpc_network" "streams-network" { name = "streams-network" }

resource "yandex_vpc_subnet" "streams-subnet-a" {
  name           = "streams-subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.streams-network.id
  v4_cidr_blocks = ["10.11.0.0/24"]
}

resource "yandex_vpc_subnet" "streams-subnet-b" {
  name           = "streams-subnet-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.streams-network.id
  v4_cidr_blocks = ["10.12.0.0/24"]
}

resource "yandex_vpc_subnet" "streams-subnet-d" {
  name           = "streams-subnet-d"
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.streams-network.id
  v4_cidr_blocks = ["10.13.0.0/24"]
}

### ydb ###
resource "yandex_vpc_security_group" "ydb-whitelist" {
  name        = "ydb-whitelist"
  description = "Правила группы разрешают доступ к базе из интернета"
  network_id  = "${yandex_vpc_network.streams-network.id}"

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к YDB endpoint"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 2135
  }

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к YDB Kafka endpoint"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 9093
  }

  ingress {
    description       = "self any"
    from_port         = 0
    predefined_target = "self_security_group"
    protocol          = "ANY"
    to_port           = 65535
  }
}

resource "yandex_ydb_database_serverless" "streams_db" {
  name                = "streams-db"
}

resource "yandex_ydb_topic" "topic_in" {
  database_endpoint = "${yandex_ydb_database_serverless.streams_db.ydb_full_endpoint}"
  name = "bank/payment-in"
  partitions_count = 1
}

resource "yandex_ydb_topic" "topic_out" {
  database_endpoint = "${yandex_ydb_database_serverless.streams_db.ydb_full_endpoint}"
  name = "bank/payment-out"
  partitions_count = 1
}


resource "yandex_iam_service_account" "db-viewer" {
  name        = "session-viewer"
  description = "service account to providing YDB connection"
}

resource "yandex_resourcemanager_folder_iam_member" "db-viewer" {
  folder_id = var.yc_folder_id
  role      = "ydb.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.db-viewer.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "db-editor" {
  folder_id = var.yc_folder_id
  role      = "ydb.editor"
  member    = "serviceAccount:${yandex_iam_service_account.db-viewer.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "db-kafka-client" {
  folder_id = var.yc_folder_id
  role      = "ydb.kafkaApi.client"
  member    = "serviceAccount:${yandex_iam_service_account.db-viewer.id}"
}

resource "yandex_iam_service_account_api_key" "streams-api-key" {
  service_account_id = yandex_iam_service_account.db-viewer.id
  description        = "api key for ydb access"
}


### flink VM ###
resource "yandex_vpc_security_group" "vm-whitelist" {
  name        = "flink-vm-whitelist"
  description = "Правила группы разрешают доступ к VM из интернета"
  network_id  = "${yandex_vpc_network.streams-network.id}"

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к кластеру по HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 8081
  }

  egress {
    protocol       = "TCP"
    description    = "Правило разрешает любые исходящие "
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_disk" "flink-boot-disk" {
  name     = "flink-boot-disk"
  type     = "network-ssd"
  zone     = "ru-central1-a"
  size     = "10"
  image_id = "fd8l45jhe4nvt0ih7h2e" # ubuntu-22-04-lts-v20240108
}
resource "yandex_compute_instance" "flink-vm" {
  name                      = "flink-vm"
  allow_stopping_for_update = true
  platform_id               = "standard-v3"
  zone                      = "ru-central1-a"
   
  resources {
    cores  = 4
    memory = 8
  }
    
  boot_disk {
    disk_id = yandex_compute_disk.flink-boot-disk.id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.streams-subnet-a.id
    nat       = true
    security_group_ids = [yandex_vpc_security_group.vm-whitelist.id]
  }
 
  metadata = {
    user-data = templatefile("${path.module}/templates/flink_vm.tpl", {
      api_key  = yandex_iam_service_account_api_key.streams-api-key.secret_key
      ydb_path = yandex_ydb_database_serverless.streams_db.database_path
    })
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}
