#######################
##### PRIVATELINK #####
#######################

output "aws_vpc_endpoint_service_domain_verification_name" {
  value = aws_vpc_endpoint_service.argocd_server[0].private_dns_name_configuration[0].name
}

output "aws_vpc_endpoint_service_domain_verification_value" {
  value = aws_vpc_endpoint_service.argocd_server[0].private_dns_name_configuration[0].value
}

#######################
######## ACM ##########
#######################

output "acm_certificate_domain_validation_options" {
  value       = module.acm.acm_certificate_domain_validation_options
  description = "A list of attributes to feed into other resources to complete certificate validation. Can have more than one element, e.g. if SANs are defined. Only set if DNS-validation was used."
}