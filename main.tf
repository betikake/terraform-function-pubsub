terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 4.84.0"
    }
  }
}

resource "google_pubsub_topic" "default" {
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
  source          = "git::https://github.com/betikake/terraform-bucket"
  bucket_name     = var.source_bucket_name
  location        = var.fun_location
  output_sha      = module.archive.output_sha
  source_code     = module.archive.source
  output_location = module.archive.output_path
  function_name   = var.function_name
}

resource "google_cloudfunctions2_function" "default" {
  name        = lower(var.function_name)
  description = var.description
  project     = var.fun_project_id
  location    = var.region

  build_config {
    runtime     = var.run_time
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = module.bucket.bucket_name
        object = module.bucket.bucket_object
      }
    }
  }

  service_config {
    available_memory               = var.available_memory
    vpc_connector                  = var.vpc_connector
    service_account_email          = var.service_account_email
    max_instance_count             = var.max_instance
    min_instance_count             = var.min_instance
    all_traffic_on_latest_revision = true
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    environment_variables          = var.environment_variables
    vpc_connector_egress_settings  = var.vpc_connector_egress_settings
  }

  labels = {
    version-crc32c = lower(replace(module.bucket.crc32c, "/\\W+/", ""))
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.default.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

}

/*
output "function_location" {
  value       = google_cloudfunctions2_function.default.service_config[0].uri
  description = "Url of the cloudfunction"
}
*/
