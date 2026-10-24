config {
  call_module_type = "local"
}

# Bundled Terraform language rules: deprecated syntax, unused declarations,
# missing types/versions, naming conventions.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}
