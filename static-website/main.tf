terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

# Static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Bucket policy that references the IAM policy
resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.policy.json
}

# IAM policy to act as the bucket policy
data "aws_iam_policy_document" "policy" {
  statement {
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
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
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# ---------------------------------------------
# CLOUDFRONT
# ---------------------------------------------

# CloudFront distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [aws_s3_bucket.bucket]
  # S3 origin
  origin {
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint
    origin_id   = aws_s3_bucket.bucket.id
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
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
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = aws_s3_bucket.bucket.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.default.id

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

# Response headers for distribution
resource "aws_cloudfront_response_headers_policy" "default" {
  name    = "${replace(var.tag_app, ".", "-")}-policy"
  comment = "Policy to ensure security headers are included"

  security_headers_config {
    # No sniffing for content
    content_type_options {
      override = true
    }
    # Iframe embedding configuration
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    # Protection against XSS
    xss_protection {
      override   = true
      protection = true
      mode_block = true
    }
    # Ensure HTTPs
    strict_transport_security {
      access_control_max_age_sec = 2628000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }
  }
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
