
// ----------------------------------------------------------------------------
// Configure Route 53 based on flags and given parameters. This will create a
// subdomain for the given apex domain zone and delegate DNS resolve to the parent
// zone
// ----------------------------------------------------------------------------
data "aws_route53_zone" "apex_domain_zone" {
  count = var.create_and_configure_subdomain && var.manage_apex_domain ? 1 : 0
  name  = "${var.apex_domain}."
}

resource "aws_route53_zone" "subdomain_zone" {
  count         = var.create_and_configure_subdomain && var.manage_subdomain ? 1 : 0
  name          = join(".", [var.subdomain, var.apex_domain])
  force_destroy = var.force_destroy_subdomain
}

resource "aws_route53_record" "subdomain_ns_delegation" {
  count   = var.create_and_configure_subdomain && var.manage_apex_domain ? 1 : 0
  zone_id = data.aws_route53_zone.apex_domain_zone[0].zone_id
  name    = join(".", [var.subdomain, var.apex_domain])
  type    = "NS"
  ttl     = 30
  records = [
    aws_route53_zone.subdomain_zone[0].name_servers[0],
    aws_route53_zone.subdomain_zone[0].name_servers[1],
    aws_route53_zone.subdomain_zone[0].name_servers[2],
    aws_route53_zone.subdomain_zone[0].name_servers[3],
  ]
}

data "aws_route53_zone" "registered_account_apex_domain_zone" {
  provider  = aws.hosted_domain
  count     = var.domain_registered_in_same_aws_account ? 0 : 1
  name      = "${var.apex_domain}."
}

resource "aws_route53_record" "registered_account_subdomain_ns_delegation" {
  provider = aws.hosted_domain
  count   = var.domain_registered_in_same_aws_account ? 0 : 1
  zone_id = data.aws_route53_zone.registered_account_apex_domain_zone[0].zone_id
  name    = join(".", [var.subdomain, var.apex_domain])
  type    = "NS"
  ttl     = 30
  records = [
    "${aws_route53_zone.subdomain_zone[0].name_servers[0]}.",
    "${aws_route53_zone.subdomain_zone[0].name_servers[1]}.",
    "${aws_route53_zone.subdomain_zone[0].name_servers[2]}.",
    "${aws_route53_zone.subdomain_zone[0].name_servers[3]}."
  ]
}
