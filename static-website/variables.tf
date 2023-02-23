# ------------------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------------------

variable "tag_app" {
  type        = string
  description = "Name for the app tag to be included in all the related resources."
}
variable "app_url" {
  type        = string
  description = "URL for the app to be created."
}
variable "aws_hosted_zone_id" {
  type        = string
  description = "ID of the existing hosted zone in AWS."
}
variable "aws_profile" {
  type        = string
  description = "Name of the profile to use."
  default     = "default"
}
variable "aws_region" {
  type        = string
  description = "Region to use."
  default     = "us-east-1"
}