data "azuread_client_config" "current_azuread" {}

data "azurerm_role_definition" "keyvault_secrets_user" {
  role_definition_id = "4633458b-17de-408a-b874-0445c86b69e6"
}
data "azurerm_role_definition" "keyvault_secrets_officer" {
  role_definition_id = "b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
}
data "azurerm_role_definition" "keyvault_certificates_officer" {
  role_definition_id = "a4417e6f-fecd-4de8-b567-7b0420556985"
}
data "azurerm_role_definition" "reader" {
  role_definition_id = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
}