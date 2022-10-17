resource "azurerm_automation_account" "automation_account" {
  name                          = "aa-demo"
  location                      = local.location
  resource_group_name           = azurerm_resource_group.rg.name
  sku_name                      = "Basic"
  public_network_access_enabled = "true"
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_automation_module" "microsoft-graph-authentication" {
  name                    = "Microsoft.Graph.Authentication"
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.automation_account.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Authentication/1.9.6"
  }
}

resource "azurerm_automation_module" "microsoft-graph-applications" {
  name                    = "Microsoft.Graph.Applications"
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.automation_account.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Applications/1.9.6"
  }
  depends_on = [
    azurerm_automation_module.microsoft-graph-authentication
  ]
}

resource "azurerm_automation_webhook" "web_book_change_spn_password" {
  name                    = "wh-change-spn-password-${random_integer.suffix.result}"
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.automation_account.name
  expiry_time             = "2032-01-01T00:00:00Z"
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.run_book_change_spn_password.name
}

resource "azurerm_automation_runbook" "run_book_change_spn_password" {
  name                    = "rb-change-spn-password-${random_integer.suffix.result}"
  location                = local.location
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.automation_account.name
  log_verbose             = "true"
  log_progress            = "true"
  description             = "Runbook for changing service principal password when PIM group assignment expires"
  runbook_type            = "PowerShell"

  content = <<EOF
 param (
    [Parameter (Mandatory = $false)]
    [object] $WebHookData
    )
    if ($WebHookData)
    {
		Write-Output "Webhook data: " $WebHookData
		# Get the connection "AzureRunAsConnection "
		$servicePrincipalConnection=Get-AutomationConnection -Name "AzureRunAsConnection"
		Connect-AzAccount -Tenant $servicePrincipalConnection.TenantID `
                             -ApplicationId $servicePrincipalConnection.ApplicationID   `
                             -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
                             -ServicePrincipal
		$targetAdAppName =  Get-AutomationVariable -Name 'AdAppName'
		$keyvaultName = Get-AutomationVariable -Name 'KeyVaultName'
		$keyvaultSecretName = Get-AutomationVariable -Name 'KeyVaultSecretName'
		Connect-MgGraph -ClientID $servicePrincipalConnection.ApplicationId -TenantId $servicePrincipalConnection.TenantId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
		# get the ad application registration
		$app = Get-MgApplication -Filter "DisplayName eq '$targetAdAppName'"
		Write-Output "application id: " $app.DisplayName
		# remove existing passwords
		foreach ($passwordCredential in $app.PasswordCredentials) {
			Remove-MgApplicationPassword -ApplicationId $app.Id -KeyId $passwordCredential.KeyId
		}
		# add new password
		$newPassword = Add-MgApplicationPassword -ApplicationId $app.Id
		Write-Output "New password created for ad app"
		$secretSecureString = ConvertTo-SecureString -String $newPassword.SecretText -AsPlainText -Force
		# set new password in keyvault secrets
		Set-AzKeyVaultSecret -VaultName $keyvaultName -Name $keyvaultSecretName -SecretValue $secretSecureString -Expires "2099-01-01T00:00:00Z"
		Write-Output "Password stored in key vault"
    }
    else
    {
        Write-Output "No webhook request body found"
    }
    EOF
}

data "azurerm_key_vault_secret" "automation_account_selfsigned_certificate_base64" {
  name         = "automation-account-certificate"
  key_vault_id = azurerm_key_vault.kv.id
  depends_on = [
    azurerm_key_vault_certificate.automation_account_selfsigned_certificate
  ]
}

resource "azurerm_automation_certificate" "automation_account_certificate" {
  name                    = "AzureRunAsCertificate"
  resource_group_name     = azurerm_automation_account.automation_account.resource_group_name
  automation_account_name = azurerm_automation_account.automation_account.name
  base64                  = data.azurerm_key_vault_secret.automation_account_selfsigned_certificate_base64.value
  exportable              = true
}

resource "azurerm_automation_connection_service_principal" "automation_account_connection_spn" {
  name                    = "AzureRunAsConnection"
  resource_group_name     = azurerm_automation_account.automation_account.resource_group_name
  automation_account_name = azurerm_automation_account.automation_account.name
  application_id          = azuread_service_principal.ad_app_automation_account_spn.application_id
  tenant_id               = local.tenant_id
  subscription_id         = local.subscription_id
  certificate_thumbprint  = azurerm_automation_certificate.automation_account_certificate.thumbprint
}

resource "azurerm_automation_variable_string" "automation_account_variable_keyvaultname" {
  name                    = "KeyVaultName"
  resource_group_name     = azurerm_automation_account.automation_account.resource_group_name
  automation_account_name = azurerm_automation_account.automation_account.name
  value                   = azurerm_key_vault.kv.name
  encrypted = false
}

resource "azurerm_automation_variable_string" "automation_account_variable_keyvaultsecretname" {
  name                    = "KeyVaultSecretName"
  resource_group_name     = azurerm_automation_account.automation_account.resource_group_name
  automation_account_name = azurerm_automation_account.automation_account.name
  value                   = local.kv_secret_name
  encrypted = false
}

resource "azurerm_automation_variable_string" "automation_account_variable_app_owner" {
  name                    = "AdAppName"
  resource_group_name     = azurerm_automation_account.automation_account.resource_group_name
  automation_account_name = azurerm_automation_account.automation_account.name
  value                   = azuread_application.ad_app.display_name
  encrypted = false
}