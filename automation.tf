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

data "azuread_service_principal" "automation_account_managed_identity" {
  display_name  = "aa-demo"

  depends_on = [
    azurerm_automation_account.automation_account
  ]
}

data "azuread_application_published_app_ids" "well_known" {}


data "azuread_service_principal" "msgraph" {
  application_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
}

resource "azuread_app_role_assignment" "app_role_assignment" {
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids["Application.ReadWrite.All"]
  principal_object_id = data.azuread_service_principal.automation_account_managed_identity.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

resource "azurerm_role_assignment" "automation_account_kv_secrets_officer" {
  lifecycle {
    ignore_changes = [role_definition_id] # see https://github.com/hashicorp/terraform-provider-azurerm/issues/4258
  }
  scope              = azurerm_key_vault.kv.id
  role_definition_id = data.azurerm_role_definition.keyvault_secrets_officer.id
  principal_id       = data.azuread_service_principal.automation_account_managed_identity.object_id
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
		Connect-AzAccount -Identity
    Write-Host -NoNewline "Current context: " Get-AzContext

		$targetAdAppName =  Get-AutomationVariable -Name 'AdAppName'
		$keyvaultName = Get-AutomationVariable -Name 'KeyVaultName'
		$keyvaultSecretName = Get-AutomationVariable -Name 'KeyVaultSecretName'

    $token = (Get-AzAccessToken -ResourceTypeName MSGraph).token
		Connect-MgGraph -AccessToken $token
    Write-Host -NoNewline "Connected to Graph API"

		$app = Get-MgApplication -Filter "DisplayName eq '$targetAdAppName'"
		Write-Host -NoNewline "Get target AD application: " $app.DisplayName
		
		foreach ($passwordCredential in $app.PasswordCredentials) {
			Remove-MgApplicationPassword -ApplicationId $app.Id -KeyId $passwordCredential.KeyId
      Write-Host -NoNewline "AD application password with KeyId: " passwordCredential.KeyId " removed"
		}

		$newPassword = Add-MgApplicationPassword -ApplicationId $app.Id
		Write-Host -NoNewline "New password *** created for AD application"
		$secretSecureString = ConvertTo-SecureString -String $newPassword.SecretText -AsPlainText -Force

		Set-AzKeyVaultSecret -VaultName $keyvaultName -Name $keyvaultSecretName -SecretValue $secretSecureString -Expires "2099-01-01T00:00:00Z"
		Write-Host -NoNewline "New password *** stored in key vault"
    }
    else
    {
        Write-Host -NoNewline "No webhook request body found"
    }
    EOF
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