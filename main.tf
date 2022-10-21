locals {
    location = "westeurope"
    tenant_id = "fec1c343-6c9a-4f19-ae25-d561a62f1b3a" # contoso
    subscription_id = "7dbaf80c-3b0d-4053-89a3-2a4a61712c71"
    kv_secret_name = "spn-password"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-demo-password-rotation"
  location = local.location
}

resource "random_integer" "suffix" {
  min  = 100
  max  = 999
  seed = "shared"
}

resource "azurerm_key_vault" "kv" {
  name                        = "kv-demo-${random_integer.suffix.result}"
  location                    = local.location
  resource_group_name         = azurerm_resource_group.rg.name
  enable_rbac_authorization   = true
  tenant_id                   = local.tenant_id
  sku_name                    = "standard"

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

resource "azurerm_role_assignment" "kv_secrets_officer" {
  lifecycle {
    ignore_changes = [role_definition_id] # see https://github.com/hashicorp/terraform-provider-azurerm/issues/4258
  }
  scope              = azurerm_key_vault.kv.id
  role_definition_id = data.azurerm_role_definition.keyvault_secrets_officer.id
  principal_id       = data.azuread_client_config.current_azuread.object_id
}

resource "azurerm_role_assignment" "kv_scertificates_officer" {
  lifecycle {
    ignore_changes = [role_definition_id] # see https://github.com/hashicorp/terraform-provider-azurerm/issues/4258
  }
  scope              = azurerm_key_vault.kv.id
  role_definition_id = data.azurerm_role_definition.keyvault_certificates_officer.id
  principal_id       = data.azuread_client_config.current_azuread.object_id
}


resource "azuread_application" "ad_app" {
  display_name            = "app-test"
  //owners                  = [data.azuread_client_config.current_azuread.object_id, azuread_service_principal.ad_app_automation_account_spn.object_id]
}

resource "azuread_service_principal" "ad_spn" {
  application_id               = azuread_application.ad_app.application_id
  //owners                  = [data.azuread_client_config.current_azuread.object_id, azuread_service_principal.ad_app_automation_account_spn.object_id]
}

resource "azuread_service_principal_password" "ad_spn_password" {
  service_principal_id = azuread_service_principal.ad_spn.object_id
}

resource "azurerm_key_vault_secret" "kv_secret" {
  name         = local.kv_secret_name
  value        = azuread_service_principal_password.ad_spn_password.value
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.kv_secrets_officer
  ]
}

resource "azuread_user" "demo_user" {
  display_name        = "J Doe"
  password            = "notSecure123"
  user_principal_name = "jdoe@M365x49226723.onmicrosoft.com"
}

resource "azuread_group" "demo_group" {
  display_name     = "Demo group"
  owners           = [data.azuread_client_config.current_azuread.object_id]
  security_enabled = true
  assignable_to_role = true
}

resource "azurerm_role_assignment" "reader" {
  lifecycle {
    ignore_changes = [role_definition_id] # see https://github.com/hashicorp/terraform-provider-azurerm/issues/4258
  }
  scope              = azurerm_key_vault.kv.id
  role_definition_id = data.azurerm_role_definition.reader.id
  principal_id       = azuread_group.demo_group.object_id
}

resource "azurerm_role_assignment" "demo_group_secrets_user" {
  lifecycle {
    ignore_changes = [role_definition_id] # see https://github.com/hashicorp/terraform-provider-azurerm/issues/4258
  }
  scope              = azurerm_key_vault.kv.id
  role_definition_id = data.azurerm_role_definition.keyvault_secrets_user.id
  principal_id       = azuread_group.demo_group.object_id
}

# https://github.com/hashicorp/terraform-provider-azurerm/issues/11475
# Due to how Azure saves certificates you need to use the data source azurerm_key_vault_secret. When you upload a certificate which has a private key to Azure Key Vault it will always create a corresponding secret for the private key.
