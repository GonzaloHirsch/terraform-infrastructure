terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.55"
    }
  }

  required_version = ">= 1.2.0"
}

# ------------------------------------------------------------------------------------------
# PROVIDER CONFIGURATION
# ------------------------------------------------------------------------------------------

provider "aws" {
  # Define AWS profile, can be default or a specific one with enough permissions
  region  = var.aws_region
  profile = var.aws_profile
}

# ------------------------------------------------------------------------------------------
# RESOURCES CONFIGURATION
# ------------------------------------------------------------------------------------------

# ---------------------------------------------
# S3
# ---------------------------------------------

# Bucket to be used
resource "aws_s3_bucket" "bucket" {
  # Simple name replaces app tag dots with dashes
  bucket = replace(var.tag_app, ".", "-")

  # No object lock
  object_lock_enabled = false

  tags = {
    app  = var.tag_app
    name = "bucket--${replace(var.tag_app, ".", "-")}"
  }
}

# Bucket policy that references the IAM policy
resource "aws_s3_bucket_policy" "allow_access_oac" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.allow_access_oac.json
}

# IAM policy to act as the bucket policy
data "aws_iam_policy_document" "allow_access_oac" {
  statement {
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    # Only access from the CDN distribution
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

# Versioning policy for NO versioning
resource "aws_s3_bucket_versioning" "no_versioning" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Disabled"
  }
}

# Blocking public access
resource "aws_s3_bucket_public_access_block" "no_public_access" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------
# CLOUDFRONT
# ---------------------------------------------

# CloudFront distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  # S3 origin
  origin {
    domain_name              = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = aws_s3_bucket.bucket.id
  }

  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_All"

  # Domain aliases
  aliases = [var.app_url, "*.${var.app_url}"]

  # SSL certificate
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.certificate.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  # No restrictions
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }

  # Allow and cache only GET, HEAD, and OPTIONS
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.bucket.id

    # No forwarding at all
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  tags = {
    app  = var.tag_app
    name = "cdn--${replace(var.tag_app, ".", "-")}"
  }
}

# OAC policy
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "oac--${replace(var.tag_app, ".", "-")}"
  description                       = "Origin Access Control policy for the ${var.tag_app} site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------
# CERTIFICATE MANAGER
# ---------------------------------------------

# Certificate itself
resource "aws_acm_certificate" "certificate" {
  # Domain name and the *.domain name
  domain_name               = var.app_url
  subject_alternative_names = ["*.${var.app_url}"]
  validation_method         = "DNS"

  tags = {
    app  = var.tag_app
    name = "cert--${replace(var.tag_app, ".", "-")}"
  }

  # Good practice to replace if the cert is in use
  lifecycle {
    create_before_destroy = true
  }
}

# Certificate validation
resource "aws_acm_certificate_validation" "validation" {
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ---------------------------------------------
# ROUTE 53
# ---------------------------------------------

# Certificate validation records
resource "aws_route53_record" "cert_validation" {
  # Create multiple records to validate the certificate
  for_each = {
    for dvo in aws_acm_certificate.certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 31536000 # 1 year
  type            = each.value.type
  zone_id         = var.aws_hosted_zone_id
}

# Record for redirecting to the CDN
resource "aws_route53_record" "domain_to_cdn" {
  zone_id = var.aws_hosted_zone_id
  name    = var.app_url
  type    = "A"

  # Alias for the CDN
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
