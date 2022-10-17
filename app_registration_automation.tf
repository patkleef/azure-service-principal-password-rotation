resource "azuread_application" "ad_app_automation_account" {
  display_name = "ad-app-automation-account"

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "18a4783c-866b-4cc7-a460-3d5e5662c884" # Application.ReadWrite.OwnedBy
      type = "Role"
    }
  }
  owners = [
    data.azuread_client_config.current_azuread.object_id
  ]
}

resource "azuread_service_principal" "ad_app_automation_account_spn" {
  application_id = azuread_application.ad_app_automation_account.application_id

  owners = [
    data.azuread_client_config.current_azuread.object_id
  ]
}

resource "azuread_app_role_assignment" "ad_app_automation_account_assignment1" {
  app_role_id         = "18a4783c-866b-4cc7-a460-3d5e5662c884" # Application.ReadWrite.OwnedBy
  principal_object_id = azuread_service_principal.ad_app_automation_account_spn.object_id
  resource_object_id  = "502d0056-951b-4d18-95ab-a00e544ba497" #MS graph

  depends_on = [
    azuread_service_principal.ad_app_automation_account_spn
  ]
}

resource "azurerm_role_assignment" "automation_account_kv_secrets_officer" {
  lifecycle {
    ignore_changes = [role_definition_id] # see https://github.com/hashicorp/terraform-provider-azurerm/issues/4258
  }
  scope              = azurerm_key_vault.kv.id
  role_definition_id = data.azurerm_role_definition.keyvault_secrets_officer.id
  principal_id       = azuread_service_principal.ad_app_automation_account_spn.object_id
}

resource "azuread_application_certificate" "ad_app_certificate" {
  application_object_id = azuread_application.ad_app_automation_account.id
  type                  = "AsymmetricX509Cert"
  value                 = azurerm_key_vault_certificate.automation_account_selfsigned_certificate.certificate_data_base64
  end_date              = azurerm_key_vault_certificate.automation_account_selfsigned_certificate.certificate_attribute[0].expires
  depends_on = [
    azurerm_key_vault_certificate.automation_account_selfsigned_certificate
  ]
}

resource "azurerm_key_vault_certificate" "automation_account_selfsigned_certificate" {
  name         = "automation-account-certificate"
  key_vault_id = azurerm_key_vault.kv.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      # Server Authentication = 1.3.6.1.5.5.7.3.1
      # Client Authentication = 1.3.6.1.5.5.7.3.2
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject_alternative_names {
        dns_names = ["*.patrickvankleef.com"]
      }

      subject            = "CN=*.patrickvankleef.com"
      validity_in_months = 12
    }
  }
  depends_on = [
    azurerm_key_vault.kv,
    azurerm_role_assignment.kv_scertificates_officer
  ]
}