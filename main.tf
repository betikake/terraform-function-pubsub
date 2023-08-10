terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.34.0"
    }
  }
}

resource "google_pubsub_topic" "topic" {
  name = var.pubsub_topic
}

resource "random_id" "bucket_prefix" {
  byte_length = var.bucket_prefix_length
}

module "archive" {
  source     = "git::https://github.com/betikake/terraform-archive"
  source_dir = var.source_dir
}

module "bucket" {
  source               = "git::https://github.com/betikake/terraform-bucket"
  bucket_name          = var.source_bucket_name
  location             = var.fun_location
  bucket_prefix_length = var.bucket_prefix_length
  project_id           = var.fun_project_id
  source_code          = module.archive.source
  output_location      = module.archive.output_path
  function_name        = var.function_name
}

resource "google_service_account" "default" {
  account_id   = var.service_account.account_id
  display_name = var.service_account.display_name
  project      = var.fun_project_id
}

//permission
resource "google_project_iam_member" "permissions_am" {
  project = var.fun_project_id
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/cloudfunctions.invoker",
    "roles/run.invoker",
    "roles/cloudsql.admin",
    "roles/cloudsql.client",
    "roles/cloudsql.editor",
    "roles/logging.admin",
    "roles/logging.logWriter",
    "roles/pubsub.publisher",
    "roles/bigquery.admin"
  ])
  role = each.key
  member  = "serviceAccount:${google_service_account.default.email}"
}

resource "google_cloudfunctions_function" "default" {
  name        = var.function_name
  description = var.description
  project     = var.fun_project_id
  runtime     = var.run_time
  entry_point = var.entry_point

  vpc_connector = var.vpc_connector

  available_memory_mb   = 128

  source_archive_bucket = module.bucket.bucket_name
  source_archive_object = module.bucket.bucket_object

  environment_variables = var.environment_variables

  labels = {
    random_value = random_id.bucket_prefix.hex
  }

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.topic.id
    failure_policy {
      retry = true
    }
  }

  service_account_email = google_service_account.default.email
}
/*
output "function_location" {
  value       = var.trigger_type == "pubsub" ? var.pubsub_topic : google_cloudfunctions2_function.default.location
  description = var.trigger_type == "pubsub" ? "Pub/Sub topic" : "URL of the Cloud Function"
}
*/
