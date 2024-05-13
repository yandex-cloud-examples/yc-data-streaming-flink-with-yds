output "instance_external_ip" {
  value = yandex_compute_instance.flink-vm.network_interface.0.nat_ip_address
}
output "api_key" {
  sensitive = true
  value = yandex_iam_service_account_api_key.streams-api-key.secret_key
}
output "database_path" {
  value = yandex_ydb_database_serverless.streams_db.database_path
}
